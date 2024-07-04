const std = @import("std");

const Square = struct {
    a: usize,

    const Self = @This();

    fn area(self: *Self) f32 {
        return @floatFromInt(self.a * self.a);
    }
};

const Cirlce = struct {
    r: usize,

    const Self = @This();

    fn area(self: *const Self) f32 {
        return 3.14 * @as(f32, @floatFromInt(self.r * self.r));
    }
};

fn Shape(comptime T: type) type {
    return struct {
        obj: *T,

        const Self = @This();

        fn init(obj: *T) Self {
            return Self{ .obj = obj };
        }

        fn area(self: Self) f32 {
            return self.obj.area();
        }
    };
}

pub fn main() void {
    var square = Square{ .a = 3 };
    square.a = 4;
    const shape = Shape(Square).init(&square);
    const cirlce = Cirlce{ .r = 2 };

    std.debug.print("{d}\n", .{shape.area()});
    std.debug.print("{d}\n", .{cirlce.area()});
}
