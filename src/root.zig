const std = @import("std");
const testing = std.testing;

var update_buffer: [64 * 64 * 1024]u8 = undefined;

extern fn updatePageHtml(ptr: [*]const u8, len: usize) void;

const AnalyzeHtmlResult = struct {
    open_or_close_count: usize,
    max_depth: usize,
};

/// htmlrender instructions
const Instr = union(enum) {
    dom_fragment: []const u8,
    text_embed: []const u8,
    attr_embed: []const u8,
    component: *fn (anytype) []const u8,
};

// fn analyzeHtml(html: []const u8, opts: struct { max_depth: usize = 1024 },) []Instr {
//     return instrs;
// }

fn renderToUpdateBuffer(comptime html: []const u8, vars: anytype, components: anytype) []const u8 {
    const instrs = comptime _: {
        var analysis = AnalyzeHtmlResult{
            .open_or_close_count = 0,
            .max_depth = 0,
        };

        // NOTE: assumes openers/closers match to avoid a stack!
        var depth: usize = 0;
        var state: enum {
            text,
            text_embed,
            tag_start,
            opener,
            closer,
            attr_key,
            attr_val_start,
            attr_val,
            self_closer,
        } = .text;
        var tok_start: usize = 0;

        // waste of comptime memory but oh well
        var instr_slots: [std.mem.count(u8, html, '<')]Instr = undefined;
        var curr_instr: usize = 0;

        // TODO: handle doc types, CDATA, etc
        for (html, 0..) |char, i| {
            switch (state) {
                .text => switch (char) {
                    '<' => {
                        state = .tag_start;
                        tok_start = i + 1;
                    },
                    '{' => {
                        state = .text_embed;
                        tok_start = i + 1;
                    },
                    else => {},
                },
                .text_embed => switch (char) {
                    '}' => {
                        state = .text;
                        const tok = html[tok_start..i];
                        instr_slots[curr_instr] = .{
                            .text_embed = @field(vars, tok),
                        };
                        curr_instr += 1;
                        tok_start = i + 1;
                    },
                    else => {},
                },
                .tag_start => switch (char) {
                    '/' => {
                        state = .self_closer;
                        tok_start = i + 1;
                    },
                    ' ' => {
                        state = .attr_key;
                        tok_start = i + 1;
                    },
                    '>' => {
                        depth += 1;
                        state = .text;
                        tok_start = i + 1;
                    },
                    else => {},
                },
                .self_closer => switch (char) {
                    '>' => {
                        result.max_depth = @max(result.max_depth, depth + 1);
                    },
                    else => {

                    },
                },
            }

            result.max_depth = @max(result.max_depth, depth + 1);
        }

        break :_ instr_slots[0..instr_count];
    };

    for (instrs) |instr| {
        switch (instrs) {
            .text_embed => {},
            .text => {},
        }
    }
}

pub fn render(comptime html: []const u8, vars: anytype, components: anytype) void {
    const result = renderToUpdateBuffer(html, vars, components);
    updatePageHtml(result.ptr, result.len);
}

test "render" {
    const x: i64 = 5;
    const y = "hello";
    const result = renderToUpdateBuffer(
        \\<div onclick={clickee}>
        \\  {x}
        \\    {y}
        \\</div>
        , .{x, y}
    );
    try testing.expectEqualStrings(result,
        \\<div onclick="zeact(1)">
        \\  5
        \\    hello
        \\</div>
    );
}
