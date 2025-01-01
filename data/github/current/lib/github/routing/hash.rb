# typed: false
# frozen_string_literal: true

module GitHub
  module Routing
    module Hash
      # S specifies the per-round shift amounts
      S = [
        7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,
        5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,
        4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,
        6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,
      ]

      # Use binary integer part of the sines of integers (Radians) as constants:
      K = [
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
        0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
        0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
        0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
        0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
        0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
        0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
        0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
        0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
        0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
        0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
        0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
        0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
      ]

      # Initialize variables:
      A0 = 0x67452301   # A
      B0 = 0xefcdab89   # B
      C0 = 0x98badcfe   # C
      D0 = 0x10325476   # D

      # route_hash() returns a short hash of `data`, suitable for use
      # in building file paths for repositories. This is used so that
      # we don't have directories with huge amounts of subdirectories,
      # but spread them out across a deeper tree with less subdirectories
      # per tree.
      #
      # Only the first 32 bytes are used in the input here. This function
      # is in no way suited nor usable for any security sensitive operation.
      # All it is intended for is to build deeper directory trees.
      def route_hash(data)
        data = data.byteslice(0, 32)
        orig_size = data.bytesize

        # Pre-processing: adding a single 1 bit
        data += 0x80.chr
        # append "1" bit to data

        # Pre-processing: padding with zeros
        padding_required = (56 - (data.bytesize % 64)) % 64
        data += 0.chr * padding_required

        # append original length in bits mod 2^64 to data
        data += [orig_size * 8].pack "Q<"
        fail unless data.bytesize == 64

        # Process the data in successive 512-bit chunks:
        m = data.unpack("V*")  # sixteen 32-bit words
        # Initialize hash value
        a, b, c, d = A0, B0, C0, D0
        # Main loop:
        (0..63).each do |i|
          if i <= 15
            f = ((b & c) | ((~b) & d)) & 0xffffffff
            g = i
          elsif i <= 31
            f = ((d & b) | ((~d) & c)) & 0xffffffff
            g = (5 * i + 1) % 16
          elsif i <= 47
            f = (b ^ c ^ d) & 0xffffffff
            g = (3 * i + 5) % 16
          else
            f = (c ^ (b | (~d))) & 0xffffffff
            g = (7 * i) % 16
          end
          # Be wary of the below definitions of a,b,c,d
          f = (f + a + K[i] + m[g]) & 0xffffffff  # M[g] must be a 32-bits block
          a = d
          d = c
          c = b
          b = (b + leftrotate(f, S[i])) & 0xffffffff
        end
        # Add this chunk's hash to result so far:
        a = A0 + a

        digest = [a].pack "V*"  # (Output is in little-endian)
        digest.unpack("H*").first
      end
      module_function :route_hash

      private

      # leftrotate function definition
      def leftrotate(x, c)
        ((x << c) | (x >> (32 - c))) & 0xffffffff
      end
      module_function :leftrotate
    end
  end
end
