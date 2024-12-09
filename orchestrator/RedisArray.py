import redis

class RedisArray:
    def __init__(self, redis_client, key, length=4096):
        self.r = redis_client
        self.key = key
        self.length = length
        # Optionally, you might want to initialize the key with empty bytes if not set
        # to ensure it's at least 'length' long. One way:
        current_val = self.r.get(self.key)
        if current_val is None or len(current_val) < self.length:
            # Pad with null bytes if too short or doesn't exist
            padding = b'\x00' * (self.length - (len(current_val) if current_val else 0))
            self.r.set(self.key, (current_val or b'') + padding)

    def __len__(self):
        return self.length

    def __getitem__(self, idx):
        if isinstance(idx, int):
            if idx < 0:
                idx = self.length + idx
            if idx < 0 or idx >= self.length:
                raise IndexError("Index out of range")
            val = self.r.getrange(self.key, idx, idx)
            # If out of range within the stored length, it might return empty bytes
            # but since we ensure length and padding, should return a byte.
            return int.from_bytes(val, byteorder='big') if val else 0
        elif isinstance(idx, slice):
            start, stop, step = idx.indices(self.length)
            if start >= stop:
                return []

            if step == 1:
                # stop is exclusive, GETRANGE end is inclusive
                data = self.r.getrange(self.key, start, stop - 1)
                return list(data)
            else:
                # Need to fetch full slice then step in Python
                data = self.r.getrange(self.key, start, stop - 1)
                return list(data)[::step]
        else:
            raise TypeError("Indices must be int or slice")

    def __setitem__(self, idx, value):
        if isinstance(idx, int):
            if idx < 0:
                idx = self.length + idx
            if idx < 0 or idx >= self.length:
                raise IndexError("Index out of range")

            if not (isinstance(value, (bytes, bytearray)) and len(value) == 1):
                raise ValueError("For single index assignment, value must be a single byte")
            self.r.setrange(self.key, idx, value)
        elif isinstance(idx, slice):
            start, stop, step = idx.indices(self.length)
            if start >= stop:
                # empty range
                if len(value) != 0:
                    raise ValueError("Attempting to assign to an empty slice")
                return

            # Compute length of slice
            slice_indices = range(start, stop, step)
            if len(value) != len(slice_indices):
                raise ValueError("Attempting to assign a slice of different length")

            if step == 1:
                # Contiguous slice
                self.r.setrange(self.key, start, value)
            else:
                # Non-contiguous slice
                # We must write each byte individually
                for pos, val_byte in zip(slice_indices, value):
                    self.r.setrange(self.key, pos, bytes([val_byte]))
        else:
            raise TypeError("Indices must be int or slice")

    def __repr__(self):
        # Just show something limited
        return f"RedisArray(key={self.key}, length={self.length})"


# Example usage:
if __name__ == "__main__":
    r = redis.Redis(host='localhost', port=6379, db=0)
    arr = RedisArray(r, 'mybytearray', length=4096)
    # Now arr has a known length of 4096 bytes.
    # arr[0] returns a byte, arr[5:10] returns a slice, arr[2:8:2] returns a stepped slice, etc.
