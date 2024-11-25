const Instr = union(enum) {
    call: *const fn (anytype) []const u8,
};

fn runDsl(comptime dsl: []const u8, funcs: anytype) void {
    comptime var instr_slots: [1]Instr = undefined;

    const instrs = comptime _: {
        const func_name = dsl[0..3];
        instr_slots[0] = .{ .call = &@field(funcs, func_name) };
        break :_ instr_slots[0..1];
    };

    inline for (instrs) |instr| {
        switch (instr) {
            .call => |c| _ = c(0),
        }
    }
}

fn func(x: anytype) []const u8 {
    _ = x;
    return "hello";
}

test {
    runDsl(
        \\Sub()
    , .{ .Sub = func });
}
