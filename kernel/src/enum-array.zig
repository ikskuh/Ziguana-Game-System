pub fn EnumArray(comptime TKey: type, comptime TValue: type) type {
    const KeyInfo = @typeInfo(TKey).Enum;

    return struct {
        const This = @This();

        fields: [KeyInfo.fields.len]TValue,

        fn keyToIndex(key: TKey) usize {
            inline for (KeyInfo.fields) |fld, i| {
                if (@intToEnum(TKey, fld.value) == key)
                    return i;
            }
            unreachable;
        }

        pub fn init(comptime value: TValue) This {
            return This{
                .fields = [_]TValue{value} ** KeyInfo.fields.len,
            };
        }

        pub fn initDefault() This {
            return This{
                .fields = [_]TValue{TValue{}} ** KeyInfo.fields.len,
            };
        }

        pub const KV = struct {
            key: TKey,
            value: TValue,
        };

        pub fn initMap(comptime initSet: []const KV) This {
            var array = This{ .fields = undefined };
            if (initSet.len != KeyInfo.fields.len)
                @compileError("Initializer map must have exact one entry per enum entry!");
            comptime var fields_inited = [_]bool{false} ** KeyInfo.fields.len;
            inline for (initSet) |kv| {
                const i = comptime keyToIndex(kv.key);
                if (fields_inited[i])
                    @compileError("Initializer map must have exact one entry per enum entry!");
                fields_inited[i] = true;
                array.fields[i] = kv.value;
            }
            return array;
        }

        pub fn at(this: This, index: TKey) TValue {
            return this.fields[keyToIndex(index)];
        }

        pub fn atMut(this: *This, index: TKey) *TValue {
            return &this.fields[keyToIndex(index)];
        }

        pub fn set(this: *This, index: TKey, val: TValue) void {
            this.fields[keyToIndex(index)] = val;
        }
    };
}

const std = @import("std");

test "EnumArray.init" {
    const E = enum {
        a,
        b,
    };
    const T = EnumArray(E, i32);

    var list = T.init(42);
    std.debug.assert(list.at(.a) == 42);
    std.debug.assert(list.at(.b) == 42);
}

test "EnumArray" {
    const E = enum {
        a,
        b,
    };
    const T = EnumArray(E, i32);

    // _ = T.initDefault();
    var list = T.initMap(([_]T.KV{
        T.KV{
            .key = .a,
            .value = 1,
        }, T.KV{
            .key = .b,
            .value = 2,
        },
    })[0..]);

    std.debug.assert(list.at(.a) == 1);
    std.debug.assert(list.at(.b) == 2);
}
