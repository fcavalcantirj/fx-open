const std = @import("std");
const image_attachments = @import("../images/image_attachments.zig");
const stream_provider = @import("../agent/stream_provider.zig");
const types = @import("../shared/types.zig");

const Allocator = std.mem.Allocator;

pub const max_sse_line_bytes: usize = 32 * 1024 * 1024;
pub const max_sse_aggregate_bytes: usize = 64 * 1024 * 1024;
pub const max_sse_events: usize = 100_000;
pub const max_tool_calls: usize = 128;
pub const max_tool_identity_bytes: usize = 1024;
pub const max_tool_arguments_bytes: usize = 4 * 1024 * 1024;
pub const max_provider_state_bytes: usize = 4 * 1024 * 1024;

pub const Limits = struct {
    aggregate_bytes: usize = max_sse_aggregate_bytes,
    events: usize = max_sse_events,
    tool_calls: usize = max_tool_calls,
    tool_identity_bytes: usize = max_tool_identity_bytes,
    tool_arguments_bytes: usize = max_tool_arguments_bytes,
    provider_state_bytes: usize = max_provider_state_bytes,
};

pub const WriteInputImageFn = *const fn (*std.Io.Writer, Allocator, image_attachments.VerifiedSnapshot) anyerror!void;

pub fn validateReplayMessage(message: types.ChatMessage, limits: Limits) !void {
    if (message.provider_state_json) |state_json| {
        if (state_json.len > limits.provider_state_bytes) return error.OpenAICodexProviderStateTooLarge;
    }
    if (message.tool_calls.len > limits.tool_calls) return error.OpenAICodexToolCallLimitExceeded;
    for (message.tool_calls) |call| {
        if (call.id.len == 0 or call.id.len > limits.tool_identity_bytes or
            call.name.len == 0 or call.name.len > limits.tool_identity_bytes)
        {
            return error.OpenAICodexToolCallLimitExceeded;
        }
        if (call.arguments_json.len > limits.tool_arguments_bytes) {
            return error.OpenAICodexToolArgumentsTooLarge;
        }
    }
}

pub fn writeInput(
    writer: *std.Io.Writer,
    alloc: Allocator,
    messages: []const types.ChatMessage,
    verified_images: ?[]const image_attachments.VerifiedSnapshot,
    write_image: WriteInputImageFn,
) !void {
    var first = true;
    for (messages, 0..) |message, message_index| {
        switch (message.role) {
            .system => continue,
            .user => {
                try writeComma(writer, &first);
                try writer.writeAll("{\"role\":\"user\",\"content\":[");
                var first_part = true;
                if (message.content) |content| if (content.len > 0) {
                    try writer.writeAll("{\"type\":\"input_text\",\"text\":");
                    try std.json.Stringify.value(content, .{}, writer);
                    try writer.writeByte('}');
                    first_part = false;
                };
                if (verified_images) |images| {
                    if (message_index == messages.len - 1) {
                        for (images) |image| {
                            if (!first_part) try writer.writeByte(',');
                            try write_image(writer, alloc, image);
                            first_part = false;
                        }
                    }
                }
                try writer.writeAll("]}");
            },
            .assistant => {
                try validateReplayMessage(message, .{});
                if (message.provider_state_json) |state_json| {
                    var state = std.json.parseFromSlice(std.json.Value, alloc, state_json, .{}) catch
                        return error.InvalidOpenAICodexProviderState;
                    defer state.deinit();
                    if (state.value != .array) return error.InvalidOpenAICodexProviderState;
                    for (state.value.array.items) |item| {
                        if (item != .object) return error.InvalidOpenAICodexProviderState;
                        try writeComma(writer, &first);
                        try std.json.Stringify.value(item, .{}, writer);
                    }
                }
                if (message.content) |content| if (content.len > 0) {
                    try writeComma(writer, &first);
                    try writer.writeAll("{\"type\":\"message\",\"role\":\"assistant\",\"status\":\"completed\",\"content\":[{\"type\":\"output_text\",\"text\":");
                    try std.json.Stringify.value(content, .{}, writer);
                    try writer.writeAll(",\"annotations\":[]}]}");
                };
                for (message.tool_calls) |call| {
                    try writeComma(writer, &first);
                    try writer.writeAll("{\"type\":\"function_call\",\"call_id\":");
                    try std.json.Stringify.value(call.id, .{}, writer);
                    try writer.writeAll(",\"name\":");
                    try std.json.Stringify.value(call.name, .{}, writer);
                    try writer.writeAll(",\"arguments\":");
                    try std.json.Stringify.value(call.arguments_json, .{}, writer);
                    try writer.writeByte('}');
                }
            },
            .tool => {
                try writeComma(writer, &first);
                try writer.writeAll("{\"type\":\"function_call_output\",\"call_id\":");
                try std.json.Stringify.value(message.tool_call_id orelse "", .{}, writer);
                try writer.writeAll(",\"output\":");
                try std.json.Stringify.value(message.content orelse "", .{}, writer);
                try writer.writeByte('}');
            },
        }
    }
}

pub fn writeComma(writer: *std.Io.Writer, first: *bool) !void {
    if (!first.*) try writer.writeByte(',');
    first.* = false;
}

pub fn writeTools(
    writer: *std.Io.Writer,
    alloc: Allocator,
    serialized_tools: []const u8,
    selected_dynamic_schemas: []const []const u8,
) !usize {
    var count: usize = 0;
    var parsed = std.json.parseFromSlice(std.json.Value, alloc, serialized_tools, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidToolSchema,
    };
    defer parsed.deinit();
    if (parsed.value != .array) return error.InvalidToolSchema;

    var tools_out: std.Io.Writer.Allocating = .init(alloc);
    defer tools_out.deinit();
    try tools_out.writer.writeAll(",\"tools\":[");
    for (parsed.value.array.items) |tool| {
        if (try writeFunctionTool(&tools_out.writer, tool, count != 0)) count += 1;
    }
    for (selected_dynamic_schemas) |schema_json| {
        var selected = std.json.parseFromSlice(std.json.Value, alloc, schema_json, .{}) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InvalidToolSchema,
        };
        defer selected.deinit();
        if (try writeFunctionTool(&tools_out.writer, selected.value, count != 0)) count += 1;
    }
    try tools_out.writer.writeByte(']');
    if (count > 0) try writer.writeAll(tools_out.written());
    return count;
}

pub fn writeFunctionTool(writer: *std.Io.Writer, value: std.json.Value, comma: bool) !bool {
    if (value != .object) return false;
    const kind = value.object.get("type") orelse return false;
    if (kind != .string or !std.mem.eql(u8, kind.string, "function")) return false;
    const name = value.object.get("name") orelse return false;
    if (name != .string or name.string.len == 0) return false;
    const parameters = value.object.get("inputSchema") orelse value.object.get("parameters") orelse return false;
    if (parameters != .object) return false;
    if (comma) try writer.writeByte(',');
    try writer.writeAll("{\"type\":\"function\",\"name\":");
    try std.json.Stringify.value(name.string, .{}, writer);
    if (value.object.get("description")) |description| if (description == .string) {
        try writer.writeAll(",\"description\":");
        try std.json.Stringify.value(description.string, .{}, writer);
    };
    try writer.writeAll(",\"parameters\":");
    try std.json.Stringify.value(parameters, .{}, writer);
    try writer.writeAll(",\"strict\":false}");
    return true;
}

pub const ToolAccumulator = struct {
    output_index: i64,
    id: []u8,
    name: []u8,
    arguments: std.ArrayList(u8) = .empty,

    pub fn deinit(self: *ToolAccumulator, alloc: Allocator) void {
        alloc.free(self.id);
        alloc.free(self.name);
        self.arguments.deinit(alloc);
        self.* = undefined;
    }
};

pub const SseReader = struct {
    pending_line: std.ArrayList(u8) = .empty,

    pub fn deinit(self: *SseReader, alloc: Allocator) void {
        self.pending_line.deinit(alloc);
    }

    fn release(self: *SseReader) void {
        self.pending_line.clearRetainingCapacity();
    }

    pub fn next(self: *SseReader, alloc: Allocator, reader: anytype) !?[]const u8 {
        while (true) {
            const line = try self.readLine(alloc, reader) orelse return null;
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == ':') {
                self.release();
                continue;
            }
            if (!std.mem.startsWith(u8, trimmed, "data:")) {
                self.release();
                continue;
            }
            const data = std.mem.trim(u8, trimmed["data:".len..], " \t");
            if (std.mem.eql(u8, data, "[DONE]")) return null;
            return data;
        }
    }

    fn readLine(self: *SseReader, alloc: Allocator, reader: anytype) !?[]const u8 {
        while (true) {
            const fragment = reader.takeDelimiter('\n') catch |err| switch (err) {
                error.StreamTooLong => {
                    const buffered = reader.buffered();
                    if (buffered.len == 0) return error.OpenAICodexSseReadStalled;
                    if (buffered.len > max_sse_line_bytes - self.pending_line.items.len) {
                        return error.OpenAICodexSseEventTooLarge;
                    }
                    try self.pending_line.appendSlice(alloc, buffered);
                    reader.tossBuffered();
                    continue;
                },
                error.ReadFailed => return error.ReadFailed,
            } orelse {
                if (self.pending_line.items.len > 0) return self.pending_line.items;
                return null;
            };
            if (fragment.len > max_sse_line_bytes - self.pending_line.items.len) {
                return error.OpenAICodexSseEventTooLarge;
            }
            if (self.pending_line.items.len == 0) return fragment;
            try self.pending_line.appendSlice(alloc, fragment);
            return self.pending_line.items;
        }
    }
};

pub fn consumeSse(
    alloc: Allocator,
    reader: anytype,
    callback_ctx: *anyopaque,
    on_content_chunk: stream_provider.StreamCallback,
    on_tool_start: ?stream_provider.ToolStartCallback,
    on_reasoning_chunk: ?stream_provider.StreamCallback,
    on_tool_input_chunk: ?stream_provider.StreamCallback,
    cancel_flag: *std.atomic.Value(bool),
    content_capture_limit: ?usize,
    limits: Limits,
) !types.GatewayCompletion {
    var content: std.ArrayList(u8) = .empty;
    errdefer content.deinit(alloc);
    var provider_state: std.Io.Writer.Allocating = .init(alloc);
    defer provider_state.deinit();
    var provider_state_count: usize = 0;
    var tools: std.ArrayList(ToolAccumulator) = .empty;
    defer {
        for (tools.items) |*tool| tool.deinit(alloc);
        tools.deinit(alloc);
    }
    var sse: SseReader = .{};
    defer sse.deinit(alloc);
    var finish_reason: ?types.ProviderFinishReason = null;
    var usage: types.Usage = .{};
    var generation_id: ?[]u8 = null;
    errdefer if (generation_id) |id| alloc.free(id);
    var terminal_seen = false;
    var saw_content_delta = false;
    var event_count: usize = 0;
    var aggregate_bytes: usize = 0;

    while (try sse.next(alloc, reader)) |json_text| {
        defer sse.release();
        if (cancel_flag.load(.seq_cst)) return error.Cancelled;
        event_count = try checkedAccumulatedSize(event_count, 1, limits.events);
        aggregate_bytes = try checkedAccumulatedSize(aggregate_bytes, json_text.len, limits.aggregate_bytes);
        var parsed = std.json.parseFromSlice(std.json.Value, alloc, json_text, .{}) catch
            return error.InvalidOpenAICodexSseEvent;
        defer parsed.deinit();
        if (parsed.value != .object) continue;
        const event_type = stringField(parsed.value.object, "type") orelse continue;

        if (std.mem.eql(u8, event_type, "response.output_item.added")) {
            const output_index = integerField(parsed.value.object, "output_index") orelse continue;
            const item = parsed.value.object.get("item") orelse continue;
            if (item != .object) continue;
            const item_type = stringField(item.object, "type") orelse continue;
            if (std.mem.eql(u8, item_type, "function_call")) {
                const call_id = stringField(item.object, "call_id") orelse continue;
                const name = stringField(item.object, "name") orelse continue;
                if (findTool(tools.items, output_index) == null) {
                    try appendTool(alloc, &tools, output_index, call_id, name, limits);
                    if (on_tool_start) |callback| callback(callback_ctx, call_id, name, null);
                }
            }
        } else if (std.mem.eql(u8, event_type, "response.output_text.delta") or
            std.mem.eql(u8, event_type, "response.refusal.delta"))
        {
            const delta = stringField(parsed.value.object, "delta") orelse continue;
            saw_content_delta = true;
            on_content_chunk(callback_ctx, delta);
            try appendCaptured(alloc, &content, delta, content_capture_limit);
        } else if (std.mem.eql(u8, event_type, "response.reasoning_summary_text.delta") or
            std.mem.eql(u8, event_type, "response.reasoning_text.delta"))
        {
            const delta = stringField(parsed.value.object, "delta") orelse continue;
            if (on_reasoning_chunk) |callback| callback(callback_ctx, delta);
        } else if (std.mem.eql(u8, event_type, "response.reasoning_summary_part.done")) {
            if (on_reasoning_chunk) |callback| callback(callback_ctx, "\n\n");
        } else if (std.mem.eql(u8, event_type, "response.function_call_arguments.delta")) {
            const output_index = integerField(parsed.value.object, "output_index") orelse continue;
            const delta = stringField(parsed.value.object, "delta") orelse continue;
            const index = findTool(tools.items, output_index) orelse continue;
            try appendToolArguments(alloc, &tools.items[index].arguments, delta, limits.tool_arguments_bytes);
            if (on_tool_input_chunk) |callback| callback(callback_ctx, delta);
        } else if (std.mem.eql(u8, event_type, "response.function_call_arguments.done")) {
            const output_index = integerField(parsed.value.object, "output_index") orelse continue;
            const arguments = stringField(parsed.value.object, "arguments") orelse continue;
            const index = findTool(tools.items, output_index) orelse continue;
            const previous_len = tools.items[index].arguments.items.len;
            if (std.mem.startsWith(u8, arguments, tools.items[index].arguments.items)) {
                const suffix = arguments[previous_len..];
                try appendToolArguments(alloc, &tools.items[index].arguments, suffix, limits.tool_arguments_bytes);
                if (suffix.len > 0) if (on_tool_input_chunk) |callback| callback(callback_ctx, suffix);
            } else {
                tools.items[index].arguments.clearRetainingCapacity();
                try appendToolArguments(alloc, &tools.items[index].arguments, arguments, limits.tool_arguments_bytes);
            }
        } else if (std.mem.eql(u8, event_type, "response.output_item.done")) {
            const output_index = integerField(parsed.value.object, "output_index") orelse continue;
            const item = parsed.value.object.get("item") orelse continue;
            if (item != .object) continue;
            const item_type = stringField(item.object, "type") orelse continue;
            if (std.mem.eql(u8, item_type, "function_call")) {
                if (findTool(tools.items, output_index)) |index| {
                    if (stringField(item.object, "arguments")) |arguments| {
                        if (tools.items[index].arguments.items.len == 0) {
                            try appendToolArguments(alloc, &tools.items[index].arguments, arguments, limits.tool_arguments_bytes);
                        }
                    }
                }
            } else if (std.mem.eql(u8, item_type, "reasoning") and
                stringField(item.object, "encrypted_content") != null)
            {
                var encoded: std.Io.Writer.Allocating = .init(alloc);
                defer encoded.deinit();
                try std.json.Stringify.value(item, .{}, &encoded.writer);
                const framed_size = try checkedAccumulatedSize(encoded.written().len, 2, limits.provider_state_bytes);
                _ = try checkedAccumulatedSize(provider_state.written().len, framed_size, limits.provider_state_bytes);
                if (provider_state_count == 0) {
                    try provider_state.writer.writeByte('[');
                } else {
                    try provider_state.writer.writeByte(',');
                }
                try provider_state.writer.writeAll(encoded.written());
                provider_state_count += 1;
            } else if (std.mem.eql(u8, item_type, "message") and !saw_content_delta) {
                if (item.object.get("content")) |parts| if (parts == .array) {
                    for (parts.array.items) |part| {
                        if (part != .object) continue;
                        const text = stringField(part.object, "text") orelse stringField(part.object, "refusal") orelse continue;
                        on_content_chunk(callback_ctx, text);
                        try appendCaptured(alloc, &content, text, content_capture_limit);
                    }
                };
            }
        } else if (std.mem.eql(u8, event_type, "response.completed") or
            std.mem.eql(u8, event_type, "response.done") or
            std.mem.eql(u8, event_type, "response.incomplete"))
        {
            const response_value = parsed.value.object.get("response") orelse continue;
            if (response_value != .object) continue;
            terminal_seen = true;
            const status = stringField(response_value.object, "status");
            finish_reason = finishReason(status, response_value.object, tools.items.len > 0);
            usage = parseUsage(response_value.object);
            if (stringField(response_value.object, "id")) |id| {
                generation_id = try alloc.dupe(u8, id);
            }
            break;
        } else if (std.mem.eql(u8, event_type, "response.failed") or
            std.mem.eql(u8, event_type, "error"))
        {
            return error.OpenAICodexResponseFailed;
        }
    }
    if (cancel_flag.load(.seq_cst)) return error.Cancelled;
    if (!terminal_seen) return error.OpenAICodexStreamIncomplete;

    const owned_content = if (content.items.len > 0) try content.toOwnedSlice(alloc) else null;
    if (owned_content != null) content = .empty;
    errdefer if (owned_content) |value| alloc.free(value);
    const owned_provider_state = if (provider_state_count > 0) state: {
        try provider_state.writer.writeByte(']');
        break :state try provider_state.toOwnedSlice();
    } else null;
    errdefer if (owned_provider_state) |value| alloc.free(value);
    const owned_tools: []types.ToolCall = if (tools.items.len > 0)
        try alloc.alloc(types.ToolCall, tools.items.len)
    else
        &.{};
    errdefer if (owned_tools.len > 0) alloc.free(owned_tools);
    var initialized: usize = 0;
    errdefer for (owned_tools[0..initialized]) |call| {
        alloc.free(call.id);
        alloc.free(call.name);
        alloc.free(call.arguments_json);
    };
    for (tools.items, 0..) |*tool, index| {
        const arguments = if (tool.arguments.items.len > 0)
            try tool.arguments.toOwnedSlice(alloc)
        else
            try alloc.dupe(u8, "{}");
        tool.arguments = .empty;
        owned_tools[index] = .{
            .id = tool.id,
            .name = tool.name,
            .arguments_json = arguments,
        };
        tool.id = &.{};
        tool.name = &.{};
        initialized += 1;
    }
    return .{
        .content = owned_content,
        .tool_calls = owned_tools,
        .generation_id = generation_id,
        .provider_state_json = owned_provider_state,
        .finish_reason = finish_reason orelse if (owned_tools.len > 0) .tool_calls else .stop,
        .usage = usage,
    };
}

pub fn appendTool(
    alloc: Allocator,
    tools: *std.ArrayList(ToolAccumulator),
    output_index: i64,
    call_id: []const u8,
    name: []const u8,
    limits: Limits,
) !void {
    if (tools.items.len >= limits.tool_calls or call_id.len == 0 or call_id.len > limits.tool_identity_bytes or
        name.len == 0 or name.len > limits.tool_identity_bytes)
    {
        return error.OpenAICodexToolCallLimitExceeded;
    }
    const id = try alloc.dupe(u8, call_id);
    errdefer alloc.free(id);
    const owned_name = try alloc.dupe(u8, name);
    errdefer alloc.free(owned_name);
    try tools.append(alloc, .{
        .output_index = output_index,
        .id = id,
        .name = owned_name,
    });
}

pub fn appendToolArguments(
    alloc: Allocator,
    arguments: *std.ArrayList(u8),
    delta: []const u8,
    maximum: usize,
) !void {
    _ = checkedAccumulatedSize(arguments.items.len, delta.len, maximum) catch
        return error.OpenAICodexToolArgumentsTooLarge;
    try arguments.appendSlice(alloc, delta);
}

pub fn checkedAccumulatedSize(current: usize, additional: usize, maximum: usize) !usize {
    const next = std.math.add(usize, current, additional) catch
        return error.OpenAICodexResourceLimitExceeded;
    if (next > maximum) return error.OpenAICodexResourceLimitExceeded;
    return next;
}

pub fn appendCaptured(
    alloc: Allocator,
    content: *std.ArrayList(u8),
    delta: []const u8,
    limit: ?usize,
) !void {
    const remaining = if (limit) |maximum| maximum -| @min(maximum, content.items.len) else delta.len;
    try content.appendSlice(alloc, delta[0..@min(delta.len, remaining)]);
}

pub fn findTool(tools: []const ToolAccumulator, output_index: i64) ?usize {
    for (tools, 0..) |tool, index| if (tool.output_index == output_index) return index;
    return null;
}

pub fn finishReason(
    status: ?[]const u8,
    response: std.json.ObjectMap,
    has_tools: bool,
) types.ProviderFinishReason {
    const value = status orelse return if (has_tools) .tool_calls else .stop;
    if (std.mem.eql(u8, value, "completed")) return if (has_tools) .tool_calls else .stop;
    if (std.mem.eql(u8, value, "incomplete")) {
        if (response.get("incomplete_details")) |details| if (details == .object) {
            if (stringField(details.object, "reason")) |reason| {
                if (std.mem.eql(u8, reason, "max_output_tokens")) return .length;
                if (std.mem.eql(u8, reason, "content_filter")) return .content_filter;
            }
        };
        return .provider_error;
    }
    if (std.mem.eql(u8, value, "failed") or std.mem.eql(u8, value, "cancelled")) return .provider_error;
    return if (has_tools) .tool_calls else .other;
}

pub fn parseUsage(response: std.json.ObjectMap) types.Usage {
    const value = response.get("usage") orelse return .{};
    if (value != .object) return .{};
    return .{
        .input_tokens = unsignedField(value.object, "input_tokens"),
        .output_tokens = unsignedField(value.object, "output_tokens"),
    };
}

pub fn stringField(object: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = object.get(key) orelse return null;
    if (value != .string) return null;
    return value.string;
}

pub fn integerField(object: std.json.ObjectMap, key: []const u8) ?i64 {
    const value = object.get(key) orelse return null;
    if (value != .integer) return null;
    return value.integer;
}

pub fn unsignedField(object: std.json.ObjectMap, key: []const u8) ?u64 {
    const value = integerField(object, key) orelse return null;
    if (value < 0) return null;
    return @intCast(value);
}

test "OpenAI Responses SSE maps text reasoning tools and usage" {
    const sse_text =
        "data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"reasoning\"}}\n\n" ++
        "data: {\"type\":\"response.reasoning_summary_text.delta\",\"output_index\":0,\"delta\":\"thinking\"}\n\n" ++
        "data: {\"type\":\"response.output_item.done\",\"output_index\":0,\"item\":{\"id\":\"rs_1\",\"type\":\"reasoning\",\"summary\":[],\"encrypted_content\":\"opaque\"}}\n\n" ++
        "data: {\"type\":\"response.output_item.added\",\"output_index\":1,\"item\":{\"type\":\"message\"}}\n\n" ++
        "data: {\"type\":\"response.output_text.delta\",\"output_index\":1,\"delta\":\"hello\"}\n\n" ++
        "data: {\"type\":\"response.output_item.added\",\"output_index\":2,\"item\":{\"type\":\"function_call\",\"call_id\":\"call_1\",\"name\":\"read_file\"}}\n\n" ++
        "data: {\"type\":\"response.function_call_arguments.delta\",\"output_index\":2,\"delta\":\"{\\\"path\\\":\\\"README.md\\\"}\"}\n\n" ++
        "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"usage\":{\"input_tokens\":10,\"output_tokens\":4}}}\n\n";
    var reader: std.Io.Reader = .fixed(sse_text);
    var cancelled = std.atomic.Value(bool).init(false);
    const Capture = struct {
        content: std.ArrayList(u8) = .empty,
        reasoning: std.ArrayList(u8) = .empty,
        saw_read_file: bool = false,

        fn contentChunk(raw: *anyopaque, chunk: []const u8) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.content.appendSlice(std.testing.allocator, chunk) catch unreachable;
        }
        fn reasoningChunk(raw: *anyopaque, chunk: []const u8) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.reasoning.appendSlice(std.testing.allocator, chunk) catch unreachable;
        }
        fn toolStart(raw: *anyopaque, _: []const u8, name: []const u8, _: ?[]const u8) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.saw_read_file = std.mem.eql(u8, name, "read_file");
        }
    };
    var capture: Capture = .{};
    defer capture.content.deinit(std.testing.allocator);
    defer capture.reasoning.deinit(std.testing.allocator);
    const completion = try consumeSse(
        std.testing.allocator,
        &reader,
        &capture,
        Capture.contentChunk,
        Capture.toolStart,
        Capture.reasoningChunk,
        null,
        &cancelled,
        null,
        .{},
    );
    defer {
        if (completion.content) |value| std.testing.allocator.free(@constCast(value));
        types.freeToolCallSlice(std.testing.allocator, @constCast(completion.tool_calls));
        if (completion.provider_state_json) |value| std.testing.allocator.free(@constCast(value));
    }
    try std.testing.expectEqualStrings("hello", capture.content.items);
    try std.testing.expectEqualStrings("thinking", capture.reasoning.items);
    try std.testing.expect(capture.saw_read_file);
    try std.testing.expectEqual(@as(usize, 1), completion.tool_calls.len);
    try std.testing.expectEqualStrings("call_1", completion.tool_calls[0].id);
    try std.testing.expectEqualStrings("{\"path\":\"README.md\"}", completion.tool_calls[0].arguments_json);
    try std.testing.expectEqual(@as(?u64, 10), completion.usage.input_tokens);
    try std.testing.expect(completion.provider_state_json != null);
    try std.testing.expect(std.mem.find(u8, completion.provider_state_json.?, "\"encrypted_content\":\"opaque\"") != null);
    try std.testing.expectEqual(types.ProviderFinishReason.tool_calls, completion.finish_reason.?);
}
