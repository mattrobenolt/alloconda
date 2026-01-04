const py = @import("alloconda");

view: ?py.BytesView = null,
start: usize = 0,
len: usize = 0,

pub const empty: @This() = .{};

pub fn fromObject(data: py.Object) !@This() {
    const view: py.BytesView = try .fromObject(data);
    const len = view.len();
    return .{ .view = view, .start = 0, .len = len };
}

pub fn fromObjectSlice(data: py.Object, start: usize, len: usize) !@This() {
    return .{
        .view = try .fromObject(data),
        .start = start,
        .len = len,
    };
}

pub fn clone(self: *const @This()) !@This() {
    const view = self.view orelse @panic("data missing");
    return .{
        .view = try view.clone(),
        .start = self.start,
        .len = self.len,
    };
}

pub fn cloneSlice(self: *const @This(), start: usize, len: usize) !@This() {
    const view = self.view orelse @panic("data missing");
    return .{
        .view = try view.clone(),
        .start = start,
        .len = len,
    };
}

pub fn slice(self: *const @This()) ![]const u8 {
    const view = self.view orelse @panic("data missing");
    const full = try view.slice();
    const end = self.start + self.len;
    if (end > full.len) @panic("data out of range");
    return full[self.start..end];
}

pub fn deinit(self: *@This()) void {
    if (self.view) |*view| {
        view.deinit();
        self.view = null;
    }
    self.* = undefined;
}
