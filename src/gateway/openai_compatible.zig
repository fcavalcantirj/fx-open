const std = @import("std");
const image_attachments = @import("../core/images/image_attachments.zig");
const openai_json = @import("../core/gateway/openai_json.zig");
const openai_responses = @import("../core/gateway/openai_responses.zig");
const openai_transport = @import("../core/gateway/openai_transport.zig");
const secret = @import("../core/auth/secret.zig");
const stream_provider = @import("../core/agent/stream_provider.zig");
const io_mod = @import("../core/shared/io.zig");
const types = @import("../core/shared/types.zig");
const gateway_client = @import("client.zig");
const openai_client = @import("openai_client.zig");

const Allocator = std.mem.Allocator;
const max_error_body_bytes: usize = 1024 * 1024;
const transfer_buffer_bytes: usize = 256 * 1024;
const connect_timeout_ms: i64 = 30_000;

pub const ApiStyle = openai_transport.ApiStyle;

pub const OpenAiCompatibleConfig = struct {
    base_url: []const u8,
    api_style: ApiStyle,
};

pub const agent_stream_provider = stream_provider.Provider{
    .build_fn = buildRequest,
    .stream_fn = streamCompletion,
};

fn configFromContext(raw: ?*anyopaque) OpenAiCompatibleConfig {
    const cfg: *const OpenAiCompatibleConfig = @ptrCast(@alignCast(raw.?));
    return cfg.*;
}

fn validateModel(model: []const u8) !void {
    if (model.len == 0 or model.len > 1024) return error.InvalidOpenAiModel;
    for (model) |byte| {
        if (byte <= 0x20 or byte == 0x7f) return error.InvalidOpenAiModel;
    }
}

fn resolveWireUrl(config: OpenAiCompatibleConfig) ![1024]u8 {
    var url_buf: [1024]u8 = undefined;
    const wire = try openai_transport.resolveWireUrl(
        &url_buf,
        config.base_url,
        config.api_style,
    );
    @memcpy(url_buf[0..wire.len], wire);
    return url_buf;
}

fn selectWireUrl(config: OpenAiCompatibleConfig, url_buf: *[1024]u8) ![]const u8 {
    const wire = try openai_transport.resolveWireUrl(url_buf, config.base_url, config.api_style);
    return switch (config.api_style) {
        .chat => openai_transport.selectE2eWireUrl(
            io_mod.getenv(openai_transport.e2e_openai_chat_url_env),
            wire,
        ),
        .responses => openai_transport.selectE2eWireUrl(
            io_mod.getenv(openai_transport.e2e_openai_responses_url_env),
            wire,
        ),
    };
}

pub fn buildRequest(
    raw_context: ?*anyopaque,
    alloc: Allocator,
    request: stream_provider.BuildRequest,
) ![]u8 {
    const config = configFromContext(raw_context);
    try validateModel(request.model);
    if (request.budget) |budget| {
        if (budget.cancel_flag) |flag| if (flag.load(.seq_cst)) return error.Cancelled;
        _ = budget.deadline;
    }

    return switch (config.api_style) {
        .chat => openai_json.buildChatCompletionsBody(
            alloc,
            request.model,
            request.serialized_tools,
            request.messages,
            request.tool_choice,
            request.max_output_tokens,
            if (request.budget) |budget|
                .{ .deadline = budget.deadline, .cancel_flag = budget.cancel_flag }
            else
                null,
        ),
        .responses => buildResponsesBody(alloc, request),
    };
}

fn ignoreInputImage(_: *std.Io.Writer, _: Allocator, _: image_attachments.VerifiedSnapshot) !void {}

fn buildResponsesBody(alloc: Allocator, request: stream_provider.BuildRequest) ![]u8 {
    var instructions: std.Io.Writer.Allocating = .init(alloc);
    defer instructions.deinit();
    for (request.messages) |message| {
        if (message.role != .system) continue;
        const text = message.content orelse continue;
        if (text.len == 0) continue;
        if (instructions.written().len > 0) try instructions.writer.writeAll("\n\n");
        try instructions.writer.writeAll(text);
    }
    if (instructions.written().len == 0) try instructions.writer.writeAll("You are a helpful assistant.");

    var out: std.Io.Writer.Allocating = .init(alloc);
    errdefer out.deinit();
    const writer = &out.writer;
    try writer.writeAll("{\"model\":");
    try std.json.Stringify.value(request.model, .{}, writer);
    try writer.writeAll(",\"store\":false,\"stream\":true,\"instructions\":");
    try std.json.Stringify.value(instructions.written(), .{}, writer);
    try writer.writeAll(",\"input\":[");
    try openai_responses.writeInput(writer, alloc, request.messages, request.verified_images, writeInputImage);
    try writer.writeByte(']');

    _ = try openai_responses.writeTools(writer, alloc, request.serialized_tools, request.selected_dynamic_tool_schemas);
    try writer.writeAll(",\"tool_choice\":");
    try std.json.Stringify.value(request.tool_choice.label(), .{}, writer);
    try writer.writeAll(",\"parallel_tool_calls\":true");

    if (request.response_format) |format| {
        try writer.writeAll(",\"text\":{\"format\":{\"type\":\"json_schema\",\"name\":");
        try std.json.Stringify.value(format.name, .{}, writer);
        try writer.writeAll(",\"description\":");
        try std.json.Stringify.value(format.description, .{}, writer);
        var schema = try std.json.parseFromSlice(std.json.Value, alloc, format.schema_json, .{});
        defer schema.deinit();
        if (schema.value != .object) return error.InvalidStructuredResponseSchema;
        try writer.writeAll(",\"schema\":");
        try std.json.Stringify.value(schema.value, .{}, writer);
        try writer.writeAll(",\"strict\":true}}");
    }

    if (request.provider_options.reasoning) |effort| {
        const label = if (std.mem.eql(u8, effort.label(), "minimal")) "low" else effort.label();
        try writer.writeAll(",\"reasoning\":{\"effort\":");
        try std.json.Stringify.value(label, .{}, writer);
        try writer.writeAll(",\"summary\":\"auto\"}");
    }

    if (request.max_output_tokens) |limit| {
        try writer.writeAll(",\"max_output_tokens\":");
        try std.json.Stringify.value(limit, .{}, writer);
    }

    try writer.writeByte('}');
    return out.toOwnedSlice();
}

fn writeInputImage(writer: *std.Io.Writer, alloc: Allocator, image: image_attachments.VerifiedSnapshot) !void {
    const encoded_len = std.base64.standard.Encoder.calcSize(image.bytes.len);
    const encoded = try alloc.alloc(u8, encoded_len);
    defer alloc.free(encoded);
    _ = std.base64.standard.Encoder.encode(encoded, image.bytes);
    try writer.writeAll("{\"type\":\"input_image\",\"detail\":\"auto\",\"image_url\":\"data:");
    try writer.writeAll(image.media_type);
    try writer.writeAll(";base64,");
    try writer.writeAll(encoded);
    try writer.writeAll("\"}");
}

fn streamCompletion(
    raw_context: ?*anyopaque,
    alloc: Allocator,
    request: stream_provider.Request,
) !stream_provider.Result {
    return streamCompletionCore(raw_context, alloc, request) catch |err| {
        if (request.cancel_flag.load(.seq_cst)) return error.Cancelled;
        request.attempt_evidence.network_failure = gateway_client.networkFailureEvidence(err, request.delivery.load());
        return err;
    };
}

fn streamCompletionCore(
    raw_context: ?*anyopaque,
    alloc: Allocator,
    request: stream_provider.Request,
) !stream_provider.Result {
    if (request.cancel_flag.load(.seq_cst)) return error.Cancelled;
    if (request.credential_source != .openai_api_key) {
        return switch (request.credential_source orelse {
            return error.OpenAiApiKeyCredentialRequired;
        }) {
            .chatgpt_subscription => error.CodexSubscriptionCredentialRequired,
            .grok_subscription => error.OpenAiCredentialCannotAuthorizeGateway,
            .ai_gateway_api_key, .vercel_oidc_token, .fx_login, .stored_key => error.OpenAiCredentialCannotAuthorizeGateway,
            .openai_api_key => unreachable,
        };
    }

    const config = configFromContext(raw_context);
    try validateModel(request.model);

    return switch (config.api_style) {
        .chat => streamChatCompletion(alloc, config, request),
        .responses => streamResponsesCompletion(alloc, config, request),
    };
}

fn streamChatCompletion(
    alloc: Allocator,
    config: OpenAiCompatibleConfig,
    request: stream_provider.Request,
) !stream_provider.Result {
    var url_buf: [1024]u8 = undefined;
    const chat_url = try selectWireUrl(config, &url_buf);
    const result = try openai_client.streamOpenAiCompletion(
        alloc,
        .{
            .api_key = request.api_key,
            .model = request.model,
            .retry_count = request.retry_count,
            .chat_url = chat_url,
            .payload = request.payload,
            .trace_ctx = request.trace_ctx,
            .content_capture_limit = request.content_capture_limit,
            .delivery = request.delivery,
            .on_tool_input_chunk = request.on_tool_input_chunk,
            .provider_attempt_owner = switch (request.provider_attempt_owner) {
                .transport => .transport,
                .agent => .agent,
            },
        },
        request.callback_ctx,
        request.on_content_chunk,
        request.on_tool_start,
        request.cancel_flag,
    );
    return .{
        .status = result.status,
        .completion = result.completion,
        .err_body = result.err_body,
        .ownership = .owned,
    };
}

const OpenedRequest = struct {
    request: ?std.http.Client.Request,

    pub fn deinit(self: *OpenedRequest, _: Allocator) void {
        if (self.request) |*req| req.deinit();
        self.request = null;
    }

    pub fn take(self: *OpenedRequest) std.http.Client.Request {
        const req = self.request.?;
        self.request = null;
        return req;
    }
};

const OpenRequestOperation = struct {
    client: *std.http.Client,
    uri: std.Uri,
    auth_header: []const u8,

    pub fn run(self: *@This()) !OpenedRequest {
        return .{ .request = try self.client.request(.POST, self.uri, .{
            .headers = .{
                .content_type = .{ .override = "application/json" },
                .authorization = .{ .override = self.auth_header },
                .accept_encoding = .omit,
                .user_agent = .{ .override = gateway_client.user_agent },
            },
            .extra_headers = &.{
                .{ .name = "accept", .value = "text/event-stream" },
            },
            .keep_alive = false,
            .redirect_behavior = .unhandled,
        }) };
    }
};

fn streamResponsesCompletion(
    alloc: Allocator,
    config: OpenAiCompatibleConfig,
    request: stream_provider.Request,
) !stream_provider.Result {
    var url_buf: [1024]u8 = undefined;
    const responses_url = try selectWireUrl(config, &url_buf);
    const auth_header = try std.fmt.allocPrint(alloc, "Bearer {s}", .{request.api_key});
    defer secret.zeroAndFree(alloc, auth_header);
    const uri = try std.Uri.parse(responses_url);

    var client: std.http.Client = .{ .allocator = alloc, .io = io_mod.getIo() };
    defer client.deinit();
    var open_operation = OpenRequestOperation{
        .client = &client,
        .uri = uri,
        .auth_header = auth_header,
    };
    const connect_deadline = std.Io.Clock.Timestamp.fromNow(io_mod.getIo(), .{
        .clock = .awake,
        .raw = .fromMilliseconds(connect_timeout_ms),
    });
    var opened = try gateway_client.runBoundedHttpOperation(
        OpenedRequest,
        alloc,
        request.cancel_flag,
        connect_deadline,
        &open_operation,
    );
    var http_request = opened.take();
    defer http_request.deinit();
    var cancel_watch_done = std.atomic.Value(bool).init(false);
    const cancel_watcher = if (http_request.connection) |connection|
        try gateway_client.spawnHttpCancelWatcher(
            &cancel_watch_done,
            request.cancel_flag,
            connection.stream_writer.stream,
        )
    else
        null;
    defer {
        cancel_watch_done.store(true, .seq_cst);
        if (cancel_watcher) |thread| thread.join();
    }
    if (request.cancel_flag.load(.seq_cst)) return error.Cancelled;

    http_request.transfer_encoding = .{ .content_length = request.payload.len };
    var send_buffer: [8192]u8 = undefined;
    request.delivery.markPossiblySent();
    var body_writer = try http_request.sendBodyUnflushed(&send_buffer);
    try body_writer.writer.writeAll(request.payload);
    try body_writer.end();
    if (http_request.connection) |connection| try connection.flush();
    if (request.cancel_flag.load(.seq_cst)) return error.Cancelled;

    var response = try http_request.receiveHead(&.{});
    if (response.head.status != .ok) {
        var transfer: [16 * 1024]u8 = undefined;
        const reader = response.reader(&transfer);
        const body = reader.allocRemaining(alloc, .limited(max_error_body_bytes)) catch |err| switch (err) {
            error.StreamTooLong => try alloc.dupe(u8, "OpenAI-compatible error response exceeded the local limit"),
            else => return err,
        };
        return .{
            .status = response.head.status,
            .err_body = body,
            .ownership = .owned,
        };
    }

    var transfer_buffer: [transfer_buffer_bytes]u8 = undefined;
    const reader = response.reader(&transfer_buffer);
    const completion = try openai_responses.consumeSse(
        alloc,
        reader,
        request.callback_ctx,
        request.on_content_chunk,
        request.on_tool_start,
        request.on_reasoning_chunk,
        request.on_tool_input_chunk,
        request.cancel_flag,
        request.content_capture_limit,
        .{},
    );
    return .{
        .status = .ok,
        .completion = completion,
        .ownership = .owned,
    };
}

test "OpenAI-compatible chat build delegates to chat completions JSON" {
    const config = OpenAiCompatibleConfig{
        .base_url = "https://api.openai.com/v1",
        .api_style = .chat,
    };
    const messages = [_]types.ChatMessage{.{ .role = .user, .content = "hello" }};
    const body = try buildRequest(@ptrCast(@constCast(&config)), std.testing.allocator, .{
        .model = "gpt-4o",
        .serialized_tools = "[]",
        .messages = &messages,
        .tool_choice = .auto,
        .provider_options = .{},
    });
    defer std.testing.allocator.free(body);
    try std.testing.expect(std.mem.find(u8, body, "\"messages\"") != null);
    try std.testing.expect(std.mem.find(u8, body, "\"input\"") == null);
}

test "OpenAI-compatible responses build includes max_output_tokens and omits service tier" {
    const config = OpenAiCompatibleConfig{
        .base_url = "https://api.openai.com/v1",
        .api_style = .responses,
    };
    const messages = [_]types.ChatMessage{.{ .role = .user, .content = "hello" }};
    const body = try buildRequest(@ptrCast(@constCast(&config)), std.testing.allocator, .{
        .model = "gpt-test",
        .serialized_tools = "[]",
        .messages = &messages,
        .tool_choice = .auto,
        .provider_options = .{ .reasoning = types.ReasoningEffort.literal("high"), .fast = true },
        .max_output_tokens = 4096,
    });
    defer std.testing.allocator.free(body);
    try std.testing.expect(std.mem.find(u8, body, "\"max_output_tokens\":4096") != null);
    try std.testing.expect(std.mem.find(u8, body, "\"service_tier\"") == null);
    try std.testing.expect(std.mem.find(u8, body, "reasoning.encrypted_content") == null);
}

test "OpenAI-compatible stream rejects non-OpenAI credentials before network I/O" {
    const config = OpenAiCompatibleConfig{
        .base_url = "https://api.openai.com/v1",
        .api_style = .chat,
    };
    var cancelled = std.atomic.Value(bool).init(false);
    var delivery = stream_provider.DeliveryCertainty.init();
    var evidence: stream_provider.AttemptEvidence = .{};
    var callback_context: u8 = 0;
    try std.testing.expectError(
        error.OpenAiCredentialCannotAuthorizeGateway,
        blk: {
            var provider = agent_stream_provider;
            provider.context = @ptrCast(@constCast(&config));
            break :blk provider.stream(std.testing.allocator, .{
                .api_key = "gateway-key",
                .credential_source = .ai_gateway_api_key,
                .team = null,
                .model = "gpt-test",
                .retry_count = 0,
                .chat_url = "https://example.invalid/chat",
                .payload = "{}",
                .trace_ctx = .{},
                .content_capture_limit = null,
                .delivery = &delivery,
                .attempt_evidence = &evidence,
                .callback_ctx = &callback_context,
                .on_content_chunk = noopStreamCallback,
                .on_tool_start = null,
                .on_reasoning_chunk = null,
                .on_tool_input_chunk = null,
                .cancel_flag = &cancelled,
            });
        },
    );
}

fn noopStreamCallback(_: *anyopaque, _: []const u8) void {}
