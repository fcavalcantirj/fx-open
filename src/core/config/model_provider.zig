const std = @import("std");
const model_catalog = @import("../gateway/model_catalog.zig");
const types = @import("../shared/types.zig");

pub const ProviderId = enum {
    gateway,
    codex,
    grok,
    openai,
};

pub const ProviderSelection = struct {
    provider: ProviderId,
    model: []const u8,
};

pub fn parse(value: []const u8) ?ProviderId {
    if (std.ascii.eqlIgnoreCase(value, "gateway")) return .gateway;
    if (std.ascii.eqlIgnoreCase(value, "codex")) return .codex;
    if (std.ascii.eqlIgnoreCase(value, "grok")) return .grok;
    if (std.ascii.eqlIgnoreCase(value, "openai")) return .openai;
    return null;
}

pub fn label(provider: ProviderId) []const u8 {
    return switch (provider) {
        .gateway => "Vercel AI Gateway",
        .codex => "Codex subscription",
        .grok => "Grok subscription",
        .openai => "OpenAI-compatible",
    };
}

pub fn authorizesCredential(provider: ProviderId, source: ?types.CredentialSource) bool {
    const selected = source orelse return false;
    return switch (provider) {
        .gateway => selected != .chatgpt_subscription and selected != .grok_subscription and selected != .openai_api_key,
        .codex => selected == .chatgpt_subscription,
        .grok => selected == .grok_subscription,
        .openai => selected == .openai_api_key,
    };
}

pub fn usesGatewayAuxiliaries(provider: ProviderId) bool {
    return provider == .gateway;
}

/// Picks a provider-switch model. When `FX_MODEL` or a saved provider model is
/// configured, that id is kept even when the catalog is empty or unavailable.
pub fn resolveSwitchModel(
    catalog_entries: []const model_catalog.ModelCatalogEntry,
    saved_model: ?[]const u8,
    process_model_override: ?[]const u8,
) ?[]const u8 {
    if (process_model_override) |raw| {
        const trimmed = std.mem.trim(u8, raw, " \t\r\n");
        if (trimmed.len > 0) {
            for (catalog_entries) |entry| {
                if (std.mem.eql(u8, entry.id, trimmed)) return entry.id;
            }
            return trimmed;
        }
    }
    if (saved_model) |candidate| {
        for (catalog_entries) |entry| {
            if (std.mem.eql(u8, entry.id, candidate)) return entry.id;
        }
        return candidate;
    }
    return if (catalog_entries.len > 0) catalog_entries[0].id else null;
}

test "explicit providers authorize only their own credential origins" {
    try std.testing.expect(authorizesCredential(.gateway, .ai_gateway_api_key));
    try std.testing.expect(authorizesCredential(.gateway, .fx_login));
    try std.testing.expect(!authorizesCredential(.gateway, .chatgpt_subscription));
    try std.testing.expect(!authorizesCredential(.gateway, .openai_api_key));
    try std.testing.expect(authorizesCredential(.codex, .chatgpt_subscription));
    try std.testing.expect(!authorizesCredential(.codex, .ai_gateway_api_key));
    try std.testing.expect(!authorizesCredential(.codex, null));
    try std.testing.expect(authorizesCredential(.openai, .openai_api_key));
    try std.testing.expect(!authorizesCredential(.openai, .ai_gateway_api_key));
    try std.testing.expect(!authorizesCredential(.openai, .chatgpt_subscription));
    try std.testing.expect(authorizesCredential(.grok, .grok_subscription));
    try std.testing.expect(!authorizesCredential(.grok, .chatgpt_subscription));
    try std.testing.expect(!authorizesCredential(.gateway, .grok_subscription));
}

test "provider parsing exposes gateway codex grok and openai" {
    try std.testing.expectEqual(ProviderId.gateway, parse("gateway").?);
    try std.testing.expectEqual(ProviderId.codex, parse("CODEX").?);
    try std.testing.expectEqual(ProviderId.grok, parse("GROK").?);
    try std.testing.expectEqual(ProviderId.openai, parse("OpenAI").?);
    try std.testing.expect(parse("openai-codex") == null);
    try std.testing.expect(parse("") == null);
}

test "openai does not use gateway auxiliaries" {
    try std.testing.expect(usesGatewayAuxiliaries(.gateway));
    try std.testing.expect(!usesGatewayAuxiliaries(.openai));
    try std.testing.expect(!usesGatewayAuxiliaries(.codex));
    try std.testing.expect(!usesGatewayAuxiliaries(.grok));
}
