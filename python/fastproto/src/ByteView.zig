const py = @import("alloconda");

data: ?py.Object = null,
start: usize = 0,
len: usize = 0,

pub const empty: @This() = .{};

pub fn init(data: ?py.Object, start: usize, len: usize) @This() {
    return .{
        .data = if (data) |obj| obj.incref() else null,
        .start = start,
        .len = len,
    };
}

pub fn slice(self: *const @This()) ![]const u8 {
    const data = self.data orelse @panic("data missing");
    const bytes: py.Bytes = .borrowed(data.ptr);
    const full = try bytes.slice();
    const end = self.start + self.len;
    if (end > full.len) @panic("data out of range");
    return full[self.start..end];
}

pub fn deinit(self: *@This()) void {
    if (self.data) |obj| {
        obj.deinit();
        self.data = null;
    }
    self.* = undefined;
}
