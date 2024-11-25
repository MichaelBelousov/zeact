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
    component: *const fn (anytype) []const u8,
};

const compdebug = false;

// fn analyzeHtml(html: []const u8, opts: struct { max_depth: usize = 1024 },) []Instr {
//     return instrs;
// }

fn renderToUpdateBuffer(comptime html: []const u8, vars: anytype, components: anytype) []const u8 {
    const instr_slot_max = comptime std.mem.count(u8, html, "<") + std.mem.count(u8, html, "{");
    comptime var instr_slots: [instr_slot_max]Instr = undefined;

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
            open_tag_name,
            open_component_name,
            close_name,
            attr_key,
            attr_val_start,
            attr_val_str,
            attr_val_embed,
            self_closer,
        } = .text;
        var tok_start: usize = 0;
        //var fragment_start: usize = 0;
        //_ = fragment_start;

        // waste of comptime memory but oh well
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
                            .text_embed = std.fmt.comptimePrint("{}", .{@field(vars, tok)}),
                        };
                        curr_instr += 1;
                        if (compdebug) @compileLog(std.fmt.comptimePrint("text_embed={s}", .{tok}));
                        tok_start = i + 1;
                    },
                    else => {},
                },
                .tag_start => switch (char) {
                    '/' => {
                        state = .close_name;
                        tok_start = i + 1;
                    },
                    'a'...'z' => {
                        state = .open_tag_name;
                        tok_start = i;
                    },
                    'A'...'Z' => {
                        state = .open_component_name;
                        tok_start = i;
                    },
                    else => @compileError(std.fmt.comptimePrint("bad opening tag at {}", .{i})),
                },
                .open_tag_name => switch (char) {
                    ' ' => {
                        state = .attr_key;
                        tok_start = i + 1;
                    },
                    '/' => {
                        state = .self_closer;
                    },
                    '>' => {
                        state = .text;
                    },
                    else => {},
                },
                .open_component_name => switch (char) {
                    ' ' => {
                        const tok = html[tok_start..i];
                        instr_slots[curr_instr] = .{
                            .component = &@field(components, tok),
                        };
                        if (compdebug) @compileLog(std.fmt.comptimePrint("open_component_name={s}", .{tok}));
                        curr_instr += 1;
                        tok_start = i + 1;
                        state = .attr_key;
                    },
                    '/' => {
                        const tok = html[tok_start..i];
                        instr_slots[curr_instr] = .{
                            .component = @field(components, tok),
                        };
                        curr_instr += 1;
                        tok_start = i + 1;
                        state = .self_closer;
                    },
                    else => {},
                },
                .attr_key => switch (char) {
                    '=' => {
                        const tok = html[tok_start..i];
                        if (compdebug) @compileLog(std.fmt.comptimePrint("attr={s}", .{tok}));
                        state = .attr_val_start;
                        tok_start = i + 1;
                    },
                    else => {},
                },
                .attr_val_start => switch (char) {
                    '"' => {
                        state = .attr_val_str;
                        tok_start = i + 1;
                    },
                    '{' => {
                        state = .attr_val_embed;
                        tok_start = i + 1;
                    },
                    else => {},
                },
                .attr_val_str => switch (char) {
                    '"' => {
                        const tok = html[tok_start..i];
                        if (compdebug) @compileLog(std.fmt.comptimePrint("attr_val_str={s}", .{tok}));
                        state = .open_tag_name;
                        tok_start = i + 1;
                    },
                    else => {},
                },
                .attr_val_embed => switch (char) {
                    '}' => {
                        const tok = html[tok_start..i];
                        if (compdebug) @compileLog(std.fmt.comptimePrint("attr_val_embed={s}", .{tok}));
                        state = .open_tag_name;
                        tok_start = i + 1;
                    },
                    else => {},
                },
                .close_name => switch (char) {
                    '>' => {
                        depth -= 1;
                        state = .text;
                        tok_start = i + 1;
                    },
                    else => {},
                },
                .self_closer => switch (char) {
                    '>' => {
                        analysis.max_depth = @max(analysis.max_depth, depth + 1);
                    },
                    else => @compileError(std.fmt.comptimePrint("bad self closer at {}", .{i})),
                },
            }

            analysis.max_depth = @max(analysis.max_depth, depth + 1);
        }

        break :_ instr_slots[0..curr_instr];
    };

    var buff = std.io.fixedBufferStream(&update_buffer);

    inline for (instrs) |instr| {
        //std.debug.print("instr={}\n", .{instr});
        switch (instr) {
            .text_embed => |v| buff.writer().print("text_embed='{s}'\n", .{v}) catch unreachable,
            .attr_embed => |v| buff.writer().print("attr_embed='{s}'\n", .{v}) catch unreachable,
            .component => |c| buff.writer().print("component?\n", .{c(0)}) catch unreachable,
            .dom_fragment => |v| buff.writer().print("fragment='{s}'\n", .{v}) catch unreachable,
        }
    }

    return update_buffer[0..buff.pos];
}

pub fn render(comptime html: []const u8, vars: anytype, components: anytype) void {
    const result = renderToUpdateBuffer(html, vars, components);
    updatePageHtml(result.ptr, result.len);
}

fn Component(props: anytype) []const u8 {
    _ = props;
    return 
    \\<span>hello</span>
    ;
}

test "render" {
    const a: i64 = 5;
    const b = "hello";

    const result = renderToUpdateBuffer(
        \\<div onClick={clickee}>
        \\  {x}
        \\  <Comp />
        \\</div>
    , .{ .x = a, .y = b }, .{ .Comp = Component });

    try testing.expectEqualStrings(
        \\<div onclick="zeact(1)">
        \\  5
        \\    <span>hello</span>
        \\</div>
    , result);
}
