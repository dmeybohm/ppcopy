# Wire Protocol

ppcopy transfers files over a parallel port using a LapLink cable. The
protocol is defined by `parread.nasm` as the source of truth; the C
implementations (`par-write.c`, `par-read.c`) follow it.

## Physical Layer

Communication uses the PC parallel port at base address `0x378`:

| Port          | Address  | Direction | Purpose          |
|---------------|----------|-----------|------------------|
| Data          | `0x378`  | Out       | Send nibbles     |
| Status        | `0x379`  | In        | Receive nibbles  |
| Control       | `0x37A`  | Out       | (unused)         |

Data is sent 4 bits (one nibble) at a time, using a clock bit for
synchronization.

## Nibble Transfer

Each nibble transfer follows this sequence:

1. **Writer** places a 4-bit value on the data port's low nibble (bits 3:0),
   combined with a clock value (bit 4).
2. **Reader** polls the status port (shifted right by 3), watching bit 4
   (the clock bit, derived from the status port's bit 7) for a toggle.
   It reads twice to confirm a stable value.
3. **Reader** sends an acknowledgment nibble (`DATA_ACK = 0x2`) back on the
   data port.

The clock alternates between `0x00` and `0x10` (writer side) for
successive nibbles.

## Octet Transfer

An octet is composed of two nibble transfers:

1. Low nibble sent with clock = `0x00`
2. High nibble sent with clock = `0x10`

The receiver reconstructs the byte: `(high << 4) | low`.

## Word Transfer

A 16-bit word is sent as two octets in **big-endian** order:

1. High byte first
2. Low byte second

The receiver reconstructs the word: `(high_byte << 8) | low_byte`.

## File Transfer Protocol

A transfer begins with a one-time start sequence, followed by one or
more data chunks, and is terminated by a size word of zero:

```
[Padding] [Start Sequence] [Chunk₁] [Chunk₂] ... [0x0000]
```

### Start Sequence

The writer sends a `0x00` padding byte followed by the six ASCII bytes
`ppcopy`. The padding byte absorbs a possible nibble-level desync when
the reader starts before the writer. The reader scans incoming octets
for the sequence `"ppcopy"` to self-synchronize.

### Reader Port Initialization

Before scanning for the start sequence, the reader writes `0x10` to the
data port (`BASE_PORT`). This ensures the writer sees a known initial
state when it begins sending.

### Chunk Structure

Each chunk carries up to ~62 KB of data (must be less than 64 KB):

```
Size                       1 word (big-endian)
Checksum                   1 word (big-endian)
Data                       `size` octets
```

- **Size**: Number of data bytes in this chunk (0 means end of file).
- **Checksum**: Simple additive sum of all data bytes in the chunk
  (unsigned 16-bit, wrapping).
- **Data**: The raw file contents for this chunk.

### Multi-Chunk Flow

For files larger than one chunk:

```
[ppcopy] [Size₁] [Checksum₁] [Data₁...]
         [Size₂] [Checksum₂] [Data₂...]
         ...
         [0x0000]  <- size of zero signals EOF
```

The start sequence is only sent once at the beginning. Subsequent chunks
follow immediately after the previous chunk's data. A size of zero
indicates the transfer is complete.

### Checksum Verification

The receiver computes its own additive sum of the received data bytes and
compares it against the received checksum. On mismatch, the transfer is
considered failed.

### Acknowledgment Code

The reader acknowledges every nibble with `DATA_ACK` (`0x2`), including
during the start sequence. The writer uses the returned ack values to
detect synchronization errors (mismatched low/high nibble acks trigger a
warning).
