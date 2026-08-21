const std = @import("std");
const model_catalog = @import("../core/gateway/model_catalog.zig");
const openai_transport = @import("../core/gateway/openai_transport.zig");
const secret = @import("../core/auth/secret.zig");
const io_mod = @import("../core/shared/io.zig");
const types = @import("../core/shared/types.zig");
const gateway_client = @import("client.zig");
const openai_compatible = @import("openai_compatible.zig");

const max_catalog_models: usize = 512;
const max_model_id_bytes: usize = 1024;
const max_catalog_bytes: usize = 4 * 1024 * 1024;
const fetch_timeout_ms: i64 = 30_000;

pub const model_catalog_provider = model_catalog.Provider{
    .fetch_fn = fetchCatalog,
};

fn configFromContext(raw: ?*anyopaque) openai_compatible.OpenAiCompatibleConfig {
    const cfg: *const openai_compatible.OpenAiCompatibleConfig = @ptrCast(@alignCast(raw.?));
    return cfg.*;
}

fn fetchCatalog(
    raw_context: ?*anyopaque,
    alloc: std.mem.Allocator,
    input: model_catalog.FetchInput,
) std.mem.Allocator.Error!model_catalog.ProviderResult {
    if (input.access.credentialSource() != .openai_api_key) {
        return .{ .failure = .{ .category = .authentication, .http_status = .unauthorized } };
    }
    const credential = input.access.authorizationCredential() orelse
        return .{ .failure = .{ .category = .authentication, .http_status = .unauthorized } };

    const config = configFromContext(raw_context);
    const request_url = modelsUrl(alloc, config.base_url) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return .{ .failure = .{ .category = .runtime } };
    };
    defer alloc.free(request_url);

    var fallback_cancel = std.atomic.Value(bool).init(false);
    const cancel_flag = input.cancel_flag orelse &fallback_cancel;
    var operation = FetchOperation{
        .alloc = alloc,
        .url = request_url,
        .credential = credential,
    };
    var response = gateway_client.runBoundedHttpOperation(
        FetchResponse,
        alloc,
        cancel_flag,
        std.Io.Clock.Timestamp.fromNow(io_mod.getIo(), .{
            .clock = .awake,
            .raw = .fromMilliseconds(fetch_timeout_ms),
        }),
        &operation,
    ) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return .{ .failure = .{
            .category = if (err == error.Cancelled) .cancellation else .transport,
            .retryable = err != error.Cancelled,
        } };
    };
    defer response.deinit(alloc);
    if (response.status != .ok) {
        return .{ .failure = model_catalog.failureForHttpStatus(response.status) };
    }
    const catalog = parseCatalog(alloc, response.body) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return .{ .failure = .{ .category = .malformed_response, .http_status = .ok } };
    };
    return .{ .catalog = catalog };
}

const FetchResponse = struct {
    status: std.http.Status,
    body: []u8,

    pub fn deinit(self: *FetchResponse, alloc: std.mem.Allocator) void {
        secret.zeroAndFree(alloc, self.body);
        self.* = undefined;
    }
};

const FetchOperation = struct {
    alloc: std.mem.Allocator,
    url: []const u8,
    credential: []const u8,

    pub fn run(self: *@This()) !FetchResponse {
        var client: std.http.Client = .{ .allocator = self.alloc, .io = io_mod.getIo() };
        defer client.deinit();
        const auth_header = try std.fmt.allocPrint(self.alloc, "Bearer {s}", .{self.credential});
        defer secret.zeroAndFree(self.alloc, auth_header);
        const body_buffer = try self.alloc.alloc(u8, max_catalog_bytes + 1);
        defer secret.zeroAndFree(self.alloc, body_buffer);
        var response_writer = std.Io.Writer.fixed(body_buffer);
        const result = client.fetch(.{
            .location = .{ .url = self.url },
            .method = .GET,
            .headers = .{
                .authorization = .{ .override = auth_header },
                .user_agent = .{ .override = gateway_client.user_agent },
                .accept_encoding = .omit,
            },
            .extra_headers = &.{
                .{ .name = "accept", .value = "application/json" },
            },
            .response_writer = &response_writer,
            .redirect_behavior = .unhandled,
        }) catch |err| switch (err) {
            error.WriteFailed => return error.OpenAiModelCatalogTooLarge,
            else => return err,
        };
        const body = response_writer.buffered();
        if (body.len > max_catalog_bytes) return error.OpenAiModelCatalogTooLarge;
        return .{
            .status = result.status,
            .body = try self.alloc.dupe(u8, body),
        };
    }
};

fn modelsUrl(alloc: std.mem.Allocator, base_url: []const u8) ![]u8 {
    const formatted = try openai_transport.formatModelsUrl(alloc, base_url);
    errdefer alloc.free(formatted);
    if (io_mod.getenv(openai_transport.e2e_openai_models_url_env)) |override| {
        if (!gateway_client.isLoopbackHttpUrl(override)) return error.InvalidE2EOpenAiModelsEndpoint;
        alloc.free(formatted);
        return alloc.dupe(u8, override);
    }
    return formatted;
}

fn parseCatalog(
    alloc: std.mem.Allocator,
    json_text: []const u8,
) !std.ArrayList(model_catalog.ModelCatalogEntry) {
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, json_text, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidOpenAiModelCatalog;
    const models_value = parsed.value.object.get("data") orelse
        return error.InvalidOpenAiModelCatalog;
    if (models_value != .array or models_value.array.items.len > max_catalog_models) {
        return error.InvalidOpenAiModelCatalog;
    }

    var catalog: std.ArrayList(model_catalog.ModelCatalogEntry) = .empty;
    errdefer model_catalog.freeModelCatalog(alloc, &catalog);
    for (models_value.array.items) |value| {
        if (value != .object) return error.InvalidOpenAiModelCatalog;
        const id = try requiredString(value.object, "id");
        try validateModelId(id);
        const owned_id = try alloc.dupe(u8, id);
        errdefer alloc.free(owned_id);
        const model_type = try alloc.dupe(u8, "language");
        errdefer alloc.free(model_type);
        try catalog.append(alloc, .{
            .id = owned_id,
            .model_type = model_type,
            .has_tool_use = true,
        });
    }
    return catalog;
}

fn requiredString(object: std.json.ObjectMap, key: []const u8) ![]const u8 {
    const value = object.get(key) orelse return error.InvalidOpenAiModelCatalog;
    if (value != .string or value.string.len == 0) return error.InvalidOpenAiModelCatalog;
    return value.string;
}

fn validateModelId(id: []const u8) !void {
    if (id.len == 0 or id.len > max_model_id_bytes) return error.InvalidOpenAiModelCatalog;
    for (id) |byte| {
        if (byte <= 0x20 or byte == 0x7f) return error.InvalidOpenAiModelCatalog;
    }
}

test "OpenAI-compatible catalog parser accepts standard models payload" {
    const alloc = std.testing.allocator;
    const json =
        \\{"data":[
        \\  {"id":"gpt-test","object":"model"},
        \\  {"id":"gpt-4o","object":"model"}
        \\]}
    ;
    var catalog = try parseCatalog(alloc, json);
    defer model_catalog.freeModelCatalog(alloc, &catalog);
    try std.testing.expectEqual(@as(usize, 2), catalog.items.len);
    try std.testing.expectEqualStrings("gpt-test", catalog.items[0].id);
}

test "OpenAI-compatible catalog rejects missing credentials" {
    const config = openai_compatible.OpenAiCompatibleConfig{
        .base_url = "https://api.openai.com/v1",
        .api_style = .chat,
    };
    const result = try fetchCatalog(@ptrCast(@constCast(&config)), std.testing.allocator, .{
        .access = .{ .public_only = .no_credential },
        .endpoint = "/v1/models",
    });
    try std.testing.expect(result.failure.category == .authentication);
}
