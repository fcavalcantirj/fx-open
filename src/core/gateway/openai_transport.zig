const std = @import("std");
const io_mod = @import("../shared/io.zig");
const types = @import("../shared/types.zig");

pub const openai_api_key_env = "OPENAI_API_KEY";
pub const openai_base_url_env = "FX_OPENAI_BASE_URL";
pub const default_base_url = "https://api.openai.com/v1";
pub const models_path = "/v1/models";
pub const chat_completions_suffix = "/chat/completions";

pub const e2e_openai_chat_url_env = "FX_E2E_OPENAI_CHAT_URL";
pub const e2e_openai_models_url_env = "FX_E2E_OPENAI_MODELS_URL";

pub fn isOpenAiCredentialSource(source: types.CredentialSource) bool {
    return source == .openai_api_key;
}

fn nonEmptyEnv(name: []const u8) ?[]const u8 {
    const raw = io_mod.getenv(name) orelse return null;
    if (std.mem.trim(u8, raw, " \t\r\n").len == 0) return null;
    return raw;
}

pub fn resolveBaseUrl() []const u8 {
    if (!active_openai_mode) return default_base_url;
    if (nonEmptyEnv(openai_base_url_env)) |value| return value;
    if (profileBaseUrl()) |url| return url;
    return default_base_url;
}

var profile_base_url_storage: [512]u8 = undefined;
var profile_base_url_len: usize = 0;
var active_openai_mode: bool = false;

pub fn setActiveOpenAiMode(active: bool) void {
    active_openai_mode = active;
}

pub fn isActiveOpenAiMode() bool {
    return active_openai_mode;
}

pub fn configureProfileBaseUrl(url: ?[]const u8) void {
    profile_base_url_len = 0;
    if (url) |value| {
        const trimmed = std.mem.trim(u8, value, " \t\r\n");
        if (trimmed.len == 0 or trimmed.len > profile_base_url_storage.len) return;
        @memcpy(profile_base_url_storage[0..trimmed.len], trimmed);
        profile_base_url_len = trimmed.len;
    }
}

fn profileBaseUrl() ?[]const u8 {
    if (profile_base_url_len == 0) return null;
    return profile_base_url_storage[0..profile_base_url_len];
}

pub fn isOpenAiChatUrl(chat_url: []const u8) bool {
    return std.mem.endsWith(u8, chat_url, chat_completions_suffix);
}

/// Writes `{base}/chat/completions` into `buf` and returns the used slice.
pub fn formatChatUrl(buf: []u8, base_url: []const u8) ![]const u8 {
    const trimmed = std.mem.trimEnd(u8, base_url, "/");
    if (std.mem.endsWith(u8, trimmed, chat_completions_suffix)) {
        if (trimmed.len > buf.len) return error.PathTooLong;
        @memcpy(buf[0..trimmed.len], trimmed);
        return buf[0..trimmed.len];
    }
    const path_suffix = if (trimmed.len == 0) chat_completions_suffix else "chat/completions";
    const total = if (trimmed.len == 0)
        path_suffix.len
    else
        trimmed.len + 1 + path_suffix.len;
    if (total > buf.len) return error.PathTooLong;
    if (trimmed.len == 0) {
        @memcpy(buf[0..path_suffix.len], path_suffix);
        return buf[0..path_suffix.len];
    }
    @memcpy(buf[0..trimmed.len], trimmed);
    buf[trimmed.len] = '/';
    @memcpy(buf[trimmed.len + 1 .. trimmed.len + 1 + path_suffix.len], path_suffix);
    return buf[0 .. trimmed.len + 1 + path_suffix.len];
}

pub fn formatModelsUrl(alloc: std.mem.Allocator, base_url: []const u8) ![]u8 {
    const trimmed = std.mem.trimEnd(u8, base_url, "/");
    if (std.mem.endsWith(u8, trimmed, "/models")) {
        return alloc.dupe(u8, trimmed);
    }
    const suffix = if (std.mem.endsWith(u8, trimmed, "/v1")) "/models" else models_path;
    if (std.mem.endsWith(u8, trimmed, "/")) {
        return std.fmt.allocPrint(alloc, "{s}{s}", .{ trimmed, suffix[1..] });
    }
    return std.fmt.allocPrint(alloc, "{s}{s}", .{ trimmed, suffix });
}

test "isActiveOpenAiMode follows selected credential flag only" {
    setActiveOpenAiMode(false);
    try std.testing.expect(!isActiveOpenAiMode());
    setActiveOpenAiMode(true);
    defer setActiveOpenAiMode(false);
    try std.testing.expect(isActiveOpenAiMode());
}

test "formatChatUrl composes base and suffix" {
    var buf: [128]u8 = undefined;
    const official = try formatChatUrl(&buf, "https://api.openai.com/v1");
    try std.testing.expectEqualStrings("https://api.openai.com/v1/chat/completions", official);

    const ollama = try formatChatUrl(&buf, "http://127.0.0.1:11434/v1/");
    try std.testing.expectEqualStrings("http://127.0.0.1:11434/v1/chat/completions", ollama);

    const already = try formatChatUrl(&buf, "http://127.0.0.1:1/v1/chat/completions");
    try std.testing.expectEqualStrings("http://127.0.0.1:1/v1/chat/completions", already);
}

test "formatModelsUrl composes OpenAI models endpoint" {
    const alloc = std.testing.allocator;
    const url = try formatModelsUrl(alloc, "https://api.openai.com/v1");
    defer alloc.free(url);
    try std.testing.expectEqualStrings("https://api.openai.com/v1/models", url);
}
