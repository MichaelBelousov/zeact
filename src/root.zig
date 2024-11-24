const std = @import("std");
const testing = std.testing;

const AnalyzeHtmlResult = struct {
    open_or_close_count: usize,
    max_depth: usize,
};

/// htmlrender instruction
const Instr = union(enum) {
    text: []const u8,
    trackedNode: struct {
        tag: []const u8,
        attrs: []const u8,
    },
};

fn analyzeHtml(html: []const u8, opts: struct { max_depth: usize = 1024 },) AnalyzeHtmlResult {
    _ = opts;

    var result = AnalyzeHtmlResult{
        .open_or_close_count = 0,
        .max_depth = 0,
    };

    // NOTE: assumes openers/closers match to avoid a stack!
    var depth: usize = 0;
    var state: enum { text, in_tag_start, in_opener, in_closer, in_attr, in_self_closer } = .text;
    var tok_start: usize = 0;

    // waste of comptime memory but oh well
    var instr_slots: [std.mem.count(u8, html, '<')]Instr = undefined;
    var instr_count: usize = 0;

    // TODO: handle doc types, CDATA, etc
    for (html, 0..) |char, i| {
        switch (state) {
            .text => switch (char) {
                '<' => {
                    state = .in_tag_start;
                    tok_start = i + 1;
                },
            },
            .in_tag_start => switch (char) {
                '/' => {
                    state = .in_self_closer;
                },
                ' ' => {
                    state = .in_attr_key;
                },
                '>' => {
                    depth += 1;
                    state = .in_text;
                },
                else => {},
            },
            .in_self_closer => switch (char) {
                '>' => {
                    result.max_depth = @max(result.max_depth, depth + 1);
                },
                '>' => {
                    depth += 1;
                    state = .in_text;
                },
            }
        }
    }

    var instrs = instr_slots[instr_count];
}

pub fn render(comptime html: []const u8, vars: anytype, components: anytype) i32 {
    const analyzed = analyzeHtml(html);
}

test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
}
