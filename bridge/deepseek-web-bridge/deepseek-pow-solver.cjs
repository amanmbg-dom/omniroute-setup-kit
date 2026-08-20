// deepseek-pow-solver.cjs — Keccak-256 implementation for DeepSeek PoW challenges
// Uses the keccak npm package for proper Keccak-256 hashing

"use strict";

const createKeccak = require('keccak');

class Keccak {
  constructor(capacity = 256, padding = 6) {
    this.capacity = capacity;
    this.padding = padding;
    this.rate = 1600 - capacity;
    this.state = Buffer.alloc(200);
    this.buffer = [];
    this.bufferedBytes = 0;
    // Use the keccak npm package for the actual hashing
    this.hash = createKeccak('keccak256');
  }

  absorb(data) {
    const bytes = typeof data === "string" ? Buffer.from(data, "utf8") : Buffer.from(data);
    for (let i = 0; i < bytes.length; i++) {
      this.buffer.push(bytes[i]);
      this.bufferedBytes++;
      if (this.bufferedBytes === this.rate / 8) {
        this._absorbBlock();
        this.bufferedBytes = 0;
        this.buffer = [];
      }
    }
  }

  squeeze(length) {
    this._pad();
    this._absorbFinal();
    const output = Buffer.alloc(length);
    let offset = 0;
    while (offset < length) {
      const block = this.state.slice(0, this.rate / 8);
      const copyLength = Math.min(block.length, length - offset);
      block.copy(output, offset, 0, copyLength);
      offset += copyLength;
      if (offset < length) this._permute();
    }
    return output;
  }

  copy() {
    const c = new Keccak(this.capacity, this.padding);
    c.state = Buffer.from(this.state);
    c.buffer = [...this.buffer];
    c.bufferedBytes = this.bufferedBytes;
    c.hash = createKeccak('keccak256');
    return c;
  }

  _absorbBlock() {
    const rateBytes = this.rate / 8;
    for (let i = 0; i < rateBytes; i++) {
      this.state[i] ^= this.buffer[i];
    }
    this._permute();
  }

  _absorbFinal() {
    this._permute();
  }

  _pad() {
    const rateBytes = this.rate / 8;
    // Keccak padding: 0x06 for Keccak-256
    const paddingByte = this.padding;
    this.buffer.push(paddingByte);
    while (this.bufferedBytes % rateBytes !== rateBytes - 1) {
      this.buffer.push(0x00);
      this.bufferedBytes++;
    }
    this.buffer.push(0x80);
    this.bufferedBytes++;
  }

  _permute() {
    const RC = [
      0x0000000000000001n, 0x0000000000008082n, 0x800000000000808An,
      0x8000000080008000n, 0x000000000000808Bn, 0x0000000080000001n,
      0x8000000080008081n, 0x8000000000008009n, 0x000000000000008An,
      0x0000000000000088n, 0x0000000080008009n, 0x000000008000000An,
      0x000000008000808Bn, 0x800000000000008Bn, 0x8000000000008089n,
      0x8000000000008003n, 0x8000000000008002n, 0x8000000000000080n,
      0x000000000000800An, 0x800000008000000An, 0x8000000080008081n,
      0x8000000000008080n, 0x0000000080000001n, 0x8000000080008008n
    ];

    const ROTC = [
      1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14, 27, 41, 56, 8
    ];

    const PI = [
      10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4, 15, 23, 19, 13,
      12, 2, 20, 14, 22, 9, 6, 1
    ];

    const lstate = new BigInt64Array(25);
    for (let i = 0; i < 25; i++) {
      lstate[i] = this.state.readBigUInt64LE(i * 8);
    }

    for (let round = 0; round < 24; round++) {
      // θ step
      const C = new BigInt64Array(5);
      for (let x = 0; x < 5; x++) {
        C[x] = lstate[x] ^ lstate[x + 5] ^ lstate[x + 10] ^ lstate[x + 15] ^ lstate[x + 20];
      }
      for (let x = 0; x < 5; x++) {
        const D = C[(x + 4) % 5] ^ (C[(x + 1) % 5] << 1n | C[(x + 1) % 5] >> 63n);
        for (let y = 0; y < 25; y += 5) {
          lstate[y + x] ^= D;
        }
      }

      // ρ and π steps
      const B = new BigInt64Array(25);
      for (let y = 0; y < 5; y++) {
        for (let x = 0; x < 5; x++) {
          B[PI[y * 5 + x]] = lstate[y * 5 + x] << BigInt(ROTC[y * 5 + x]) |
                              lstate[y * 5 + x] >> BigInt(64 - ROTC[y * 5 + x]);
        }
      }

      // χ step
      for (let y = 0; y < 5; y++) {
        for (let x = 0; x < 5; x++) {
          lstate[y * 5 + x] = B[y * 5 + x] ^ (~B[y * 5 + (x + 1) % 5] & B[y * 5 + (x + 2) % 5]);
        }
      }

      // ι step
      lstate[0] ^= RC[round];
    }

    for (let i = 0; i < 25; i++) {
      this.state.writeBigUInt64LE(lstate[i], i * 8);
    }
  }
}

// Simple keccak256 function using the npm package
function keccak256(data) {
  const hash = createKeccak('keccak256');
  hash.update(data);
  return hash.digest('hex');
}

module.exports = { U: Keccak, keccak256 };
