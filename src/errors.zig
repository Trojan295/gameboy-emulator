pub const MemoryError = error{
    WriteNotAllowed,
};

pub const DisplayError = error{
    InitFailed,
};

pub const CartridgeError = error{
    UnknownMBC,
};
