"""Byte-assembled TIFF fixtures with formula-defined synthetic sample truth."""
import argparse
import csv
import hashlib
import itertools
import json
from pathlib import Path
import struct
import zlib

import numpy as np


def packbits(raw):
    result = bytearray()
    i = 0
    while i < len(raw):
        n = 1
        while i + n < len(raw) and raw[i + n] == raw[i] and n < 128:
            n += 1
        if n >= 3:
            result.extend((257 - n, raw[i])); i += n
        else:
            begin = i
            i += n
            while i < len(raw) and i - begin < 128:
                n = 1
                while i + n < len(raw) and raw[i + n] == raw[i] and n < 3:
                    n += 1
                if n == 3:
                    break
                i += min(n, 128 - (i - begin))
            result.append(i - begin - 1)
            result.extend(raw[begin:i])
    return bytes(result)


def lzw(raw):
    """TIFF MSB-first LZW, early-change decoder convention and bounded resets."""
    codes = []
    width = 9
    table = {bytes([i]): i for i in range(256)}
    next_code = 258
    codes.append((256, width))
    word = b''
    for byte in raw:
        candidate = word + bytes([byte])
        if candidate in table:
            word = candidate
            continue
        codes.append((table[word], width))
        table[candidate] = next_code
        next_code += 1
        if next_code == 1 << width and width < 12:
            width += 1
        if next_code == 4095:
            codes.append((256, width))
            table = {bytes([i]): i for i in range(256)}
            width, next_code = 9, 258
        word = bytes([byte])
    if word:
        codes.append((table[word], width))
        if next_code == (1 << width) - 1 and width < 12:
            width += 1
    codes.append((257, width))
    bits = ''.join(f'{code:0{n}b}' for code, n in codes)
    bits += '0' * (-len(bits) % 8)
    return bytes(int(bits[i:i + 8], 2) for i in range(0, len(bits), 8)), {
        'max_code_width': max(n for _, n in codes),
        'clear_codes': sum(c == 256 for c, _ in codes),
        'dictionary_codes': sum(c > 257 for c, _ in codes)}


def truth(height, width, channels, bits, floating=False, page_index=0):
    r, c, ch = np.indices((height, width, channels), dtype=np.int64)
    if floating:
        data = ((r * 37 + c * 11 + ch * 19 + page_index * 7) % 2048 - 1024) / 16
        data = data.astype(np.float32)
        data[0, 0, :] = -0.5
        data[-1, -1, :] = 2**20
    else:
        maximum = 2**bits - 1
        data = ((r * 2654435761) ^ (c * 2246822519) ^ (ch * 3266489917) ^
                (r * c * 31) ^ (page_index * 101)) & maximum
        data = data.astype(np.uint64)
        data[0, 0, :] = 0
        data[0, 1, :] = np.arange(channels) + 1
        data[-1, -1, :] = maximum - np.arange(channels)
    return data


def encoded_segments(data, bits, floating, endian, storage, codec, predictor):
    height, width, channels = data.shape
    blocks = []
    if storage == 'strips':
        blocks = [data[r:r + 3] for r in range(0, height, 3)]
    else:
        for r in range(0, height, 16):
            for c in range(0, width, 16):
                block = np.zeros((16, 16, channels), dtype=data.dtype)
                part = data[r:r + 16, c:c + 16]
                block[:part.shape[0], :part.shape[1], :] = part
                blocks.append(block)
    segments, stats = [], []
    dtype = ('<' if endian == 'little' else '>') + (f'f{bits // 8}' if floating else f'u{bits // 8}')
    for block in blocks:
        encoded = block.copy()
        if predictor == 2:
            assert not floating
            encoded[:, 1:, :] = (block[:, 1:, :] - block[:, :-1, :]) & (2**bits - 1)
        raw = encoded.astype(dtype).tobytes(order='C')
        if codec == 'lzw':
            payload, details = lzw(raw); stats.append(details)
        elif codec == 'deflate':
            payload = zlib.compress(raw, level=6)
        elif codec == 'packbits':
            # PackBits runs do not cross a scanline boundary.
            row_bytes = encoded.shape[1] * channels * (bits // 8)
            payload = b''.join(packbits(raw[i:i + row_bytes]) for i in range(0, len(raw), row_bytes))
        else:
            payload = raw
        segments.append(payload)
    return segments, stats


def page_bytes(base, data, bits, floating, endian, storage, codec, predictor=1,
               photometric=None, planar=1, orientation=1, sample_format=None, last=True):
    height, width, channels = data.shape
    segments, stats = encoded_segments(data, bits, floating, endian, storage, codec, predictor)
    if planar == 2:
        segments, stats = [], []
        for channel in range(channels):
            pieces, details = encoded_segments(data[:, :, channel:channel + 1], bits, floating,
                                               endian, storage, codec, predictor)
            segments.extend(pieces); stats.extend(details)
    fmt = '<' if endian == 'little' else '>'
    uint = lambda n, length: int(n).to_bytes(length, endian)
    tags = {256: (4, [width]), 257: (4, [height]), 258: (3, [bits] * channels),
            259: (3, [{'none': 1, 'lzw': 5, 'deflate': 8, 'packbits': 32773}[codec]]),
            262: (3, [photometric if photometric is not None else (2 if channels >= 3 else 1)]),
            274: (3, [orientation]), 277: (3, [channels]), 284: (3, [planar]),
            339: (3, [sample_format if sample_format is not None else 3 if floating else 1] * channels)}
    if predictor != 1:
        tags[317] = (3, [predictor])
    if channels in (2, 4):
        tags[338] = (3, [2])
    offsets_tag, counts_tag = (273, 279) if storage == 'strips' else (324, 325)
    tags[offsets_tag] = (4, [0] * len(segments))
    tags[counts_tag] = (4, [len(p) for p in segments])
    if storage == 'strips':
        tags[278] = (4, [3])
    else:
        tags[322], tags[323] = (4, [16]), (4, [16])
    end_ifd = base + 2 + len(tags) * 12 + 4
    external_size = sum(len(v) * (2 if t == 3 else 4) for t, v in tags.values()
                        if len(v) * (2 if t == 3 else 4) > 4)
    data_start = end_ifd + external_size
    cursor = data_start
    offsets = []
    for segment in segments:
        offsets.append(cursor); cursor += len(segment)
    tags[offsets_tag] = (4, offsets)
    external = bytearray()
    entries = bytearray()
    for tag, (kind, values) in sorted(tags.items()):
        payload = b''.join(uint(v, 2 if kind == 3 else 4) for v in values)
        if len(payload) > 4:
            slot = uint(end_ifd + len(external), 4); external.extend(payload)
        else:
            slot = payload.ljust(4, b'\0')
        entries.extend(struct.pack(fmt + 'HHI', tag, kind, len(values)) + slot)
    padding = b'\0' * (cursor % 2)
    next_ifd = 0 if last else cursor + len(padding)
    body = uint(len(tags), 2) + entries + uint(next_ifd, 4) + external + b''.join(segments) + padding
    return body, stats


def write_file(path, pages, endian, codec, storage, predictor=1):
    raw = (b'II' if endian == 'little' else b'MM') + (42).to_bytes(2, endian) + (8).to_bytes(4, endian)
    stats = []
    for i, (data, bits, floating, extra) in enumerate(pages):
        body, details = page_bytes(len(raw), data, bits, floating, endian, storage,
                                   codec, predictor, last=i == len(pages) - 1, **extra)
        raw += body; stats.extend(details)
    path.write_bytes(raw)
    return stats


def fixture_stem(label, bits, channels, floating, endian, storage, codec, predictor):
    """Keep package tar member names below the portable 100-byte limit."""
    layout = 's' if storage == 'strips' else 't'
    byte_order = 'le' if endian == 'little' else 'be'
    sample = 'f' if floating else 'u'
    return f'{label}_{codec}_{layout}_{byte_order}_{sample}{bits}_c{channels}_p{predictor}'


def main(out):
    out.mkdir(parents=True, exist_ok=False)
    records = []
    layouts = [(8,1,False),(16,1,False),(32,1,False),(32,1,True),
               (8,3,False),(16,3,False),(32,3,False),(32,3,True),(8,4,False),(16,2,False)]
    def create(label, bits, channels, floating, endian, storage, codec, predictor=1, height=17, width=19, extra=None, expected='pass', pages=1):
        ident = fixture_stem(label, bits, channels, floating, endian, storage, codec, predictor)
        path = out / (ident + '.tif')
        inputs = [(truth(height + i, width + 2*i, channels, bits, floating, i), bits, floating, extra or {}) for i in range(pages)]
        stats = write_file(path, inputs, endian, codec, storage, predictor)
        for page, (data, _, _, _) in enumerate(inputs, 1):
            for channel in range(channels):
                expected_path = out / f'{ident}_pg{page}_ch{channel+1}.csv'
                np.savetxt(expected_path, data[:, :, channel].astype(np.float64), delimiter=',', fmt='%.17g')
                records.append({'fixture':path.name,'expected_values':expected_path.name,'expectation':expected,
                                'page':page,'pages':pages,'channel':channel+1,'channels':channels,
                                'height':data.shape[0],'width':data.shape[1],'bits':bits,
                                'sample_format':'float' if floating else 'uint','codec':codec,'storage':storage,
                                'byte_order':endian,'predictor':predictor,'label':label})
        return stats
    for codec, storage, endian, layout in itertools.product(('lzw','deflate','packbits'),('strips','tiles'),('little','big'),layouts):
        create('core',*layout,endian,storage,codec)
    for codec, storage, endian, bits, channels in itertools.product(('lzw','deflate'),('strips','tiles'),('little','big'),(8,16,32),(1,3)):
        create('horizontal',bits,channels,False,endian,storage,codec,predictor=2)
    stress = []
    for endian in ('little','big'):
        stress.extend(create('dictionary',8,1,False,endian,'strips','lzw',height=3,width=20011))
        for codec in ('lzw','deflate','packbits'):
            create('multipage',16,1,False,endian,'strips',codec,pages=3)
    for name, extra, floating, bits, channels in [
        ('signed',{'sample_format':2},False,16,1),('whitezero',{'photometric':0},False,8,1),
        ('palette',{'photometric':3},False,8,1),('separate',{'planar':2},False,8,3),
        ('float64',{},True,64,1)]:
        create(name,bits,channels,floating,'little','strips','deflate',extra=extra,expected='refuse')
    for orientation in range(2,9):
        create(f'orientation{orientation}',8,1,False,'little','strips','deflate',extra={'orientation':orientation},expected='refuse')
    with (out/'matrix.csv').open('w',newline='') as stream:
        writer=csv.DictWriter(stream,fieldnames=list(records[0]));writer.writeheader();writer.writerows(records)
    (out/'generation.json').write_text(json.dumps({'files':len({r['fixture'] for r in records}),
        'channel_page_comparisons':len(records),'lzw_stress_max_width':max(s['max_code_width'] for s in stress),
        'lzw_stress_clear_codes':sum(s['clear_codes'] for s in stress),
        'lzw_stress_dictionary_codes':sum(s['dictionary_codes'] for s in stress),
        'generator_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'numpy':np.__version__,'zlib':zlib.ZLIB_RUNTIME_VERSION,
        'truth':'Fixed row/column/channel formula; expected CSVs written before any package read.'},indent=2)+'\n')
    print(json.dumps({'fixtures':len({r['fixture'] for r in records}),'comparisons':len(records)}))


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('output',type=Path)
    main(parser.parse_args().output)
