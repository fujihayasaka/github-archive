# typed: true
# frozen_string_literal: true

# Public: An ActiveRecord column type for values containing Integer arrays.
#
# Values for attributes that use this column type are stored as a packed binary string in a
# blob column in the database. The pack format is determined by the largest value in the
# array:
#
# - if all values are less than 16 they will be stored as nibbles, where pairs of nibbles
#   are combined into bytes for packing/unpacking
# - if all values are between 16 and 255 they will be stored as bytes
# - if all values are between 256 and 65535 they will be stored as smallints (2 bytes)
# - if any value is greater than 65535 they will be stored as ints (4 bytes)
#
# The compression format includes optimization for cases where there are many zero values, or
# where there is only one nonzero element in the array. This column format works well for use
# cases where the values in the array don't need to be queried and tend to be very small and
# can be packed as bytes or nibbles. Such use cases include commit contributions, where a
# large majority of users contribute fewer than 16 commits per day/repo.
#
# Header byte format:
#
# bit 87654321
#     1xxxxxxx - reserved for future use
#     x111xxxx - compression format
#     xxxx11xx - size of array count(s) - total count and optional nonzero count
#     xxxxxx11 - data size
#
# Supported values for compression format are:
#
# 000 - multi_value: one count value (N=total count) followed by N values
# 001 - multi_sparse: two count values (total count and N=nonzero count) followed by N indexes and N values
# 010 - single_value: one total count value (nonzero count is 1) followed by one index and one value
# 011 - single_one: one total count value (nonzero count is 1) followed by one index
# 100 - multi_sparse_offset: two count values (total count and N=nonzero count) followed by N offset indexes and N values
#
# Supported values for count/data size are:
#
# 00 - nibble (4 bits)
# 01 - byte (8 bits)
# 10 - smallint (16 bits)
# 11 - int (32 bits)
#
# Example format when all array values are less than 16 - eg. [1, 2, 3, 4, 5, 6, 7, 8, 9],
# stored as a 7-byte string:
#
# > CompressedIntegerArray.new.serialize([1,2,3,4,5,6,7,8,9]).bytes.map { |b| "0x%02x" % b }.join(" ")
# => "0x00 0x09 0x12 0x34 0x56 0x78 0x90"

#
# Header   Counts   Data
# 0x00     0x09     0x12     0x34     0x56     0x78     0x9a
# 00000000 00001001 00010010 00110100 01010110 01111000 10010000
#   CF|||| ^^CD^^UN ^^E1^^E2 ^^E3^^E4 ^^E5^^E6 ^^E7^^E8 ^^E9^^UN
#     CS||
#       DS
#
# CF: compression format, 00 = 0x00 = :multi_value
# CS: count size,         00 = 0x00 = nibble/4 bits
# DS: data size ,         00 = 0x00 = nibble/4 bits
# TC: total count,      1001 = 0x09 = 9 total elements in array
# E1: element 1,        0001 = 0x01 = 1
# E2: element 2,        0010 = 0x02 = 2
# E3: element 3,        0011 = 0x03 = 3
# ...
# E5: element 9,        1001 = 0x09 = 9
# UN: unused/padding
#
#
# Example sparse format with many nonzero values - eg. [0, 0, 1, 5, 0, 0, 3, 0, 2], stored as a 4-byte string:
#
# > CompressedIntegerArray.new.serialize([0,0,1,5,0,0,0,3,0,2]).bytes.map { |b| "0x%02x" % b }.join(" ")
# => "0x10 0x94 0x23 0x68 0x15 0x32"
#
# Header   Counts   Data
# 0x10     0x94     0x23     0x68     0x15     0x32
# 00010000 10010100 00100011 01101000 00010101 00110010
#   CF|||| ^^TC^^NC ^^I1^^I2 ^^I3^^I4 ^^E1^^E2 ^^E3^^E4
#     CS||
#       DS
#
# CF: compression format, 01 = 0x01 = :multi_sparse
# CS: count size,         00 = 0x00 = nibble/4 bits
# DS: data size,          00 = 0x00 = nibble/4 bits
# TC: total count,      1001 = 0x09 = 9 total elements in array
# NC: nonzero count,    0100 = 0x04 = 4 nonzero elements in array
# I1: index 1,          0010 = 0x02 = 2
# I2: index 2,          0011 = 0x03 = 3
# I3: index 3,          0110 = 0x06 = 6
# I4: index 4,          1000 = 0x08 = 8
# E1: element 1,        0001 = 0x01 = 1
# E2: element 2,        0101 = 0x05 = 5
# E3: element 3,        0011 = 0x03 = 3
# E4: element 4,        0010 = 0x02 = 2
#
#
# Example format with a single nonzero value - eg. Array.new(365, 0).fill(42, 180, 1), stored as a 5-byte string:
#
# > CompressedIntegerArray.new.serialize(Array.new(365, 0).fill(42, 180, 1)).bytes.map { |b| "0x%02x" % b }.join(" ")
# => "0x29 0x6d 0x01 0xb4 0x2a"
#
# Header   Total Count       Index    Value
# 0x29     0x16d             0xb4     0x2a
# 00101001 01101101 00000001 10110100 00101010
#   CF|||| ^^^^^^^^ ^^^^^^TC ^^^^^^I1 ^^^^^^E1
#     CS||
#       DS
#
# CF: compression format, 10 = 0x02 = :single_value
# CS: count size,         10 = 0x00 = smallint/16 bits
# DS: data size,          01 = 0x01 = byte/8 bits
# TC: total count,           0x016d = 365 total elements in array
# I1: index 1,      10110100 = 0xb4 = 180
# E1: element 1,    00101010 = 0x2a = 42
#
#
# Example format with a single nonzero value of 1 - eg. Array.new(365, 0).fill(1, 180, 1), stored as a 4-byte string:
#
# > CompressedIntegerArray.new.serialize(Array.new(365, 0).fill(1, 180, 1)).bytes.map { |b| "0x%02x" % b }.join(" ")
# => "0x39 0x6d 0x01 0xb4"
#
# Header   Total Count       Index
# 0x39     0x16d             0xb4
# 00111001 01101101 00000001 10110100
#   CF|||| ^^^^^^^^ ^^^^^^TC ^^^^^^I1
#     CS||
#       DS
#
# CF: compression format, 11 = 0x03 = :single_one
# CS: count size,         10 = 0x00 = smallint/16 bits
# DS: data size,          01 = 0x01 = byte/8 bits
# TC: total count,           0x016d = 365 total elements in array
# I1: index 1,      10110100 = 0xb4 = 180
#
#
# Example usage in an ActiveRecord model:
#
# class ContributionSummary < ActiveRecord::Base
#   attribute :counts, CompressedIntegerArray.new
# end
#
# CommitContributionSummary.create(counts: [1, 2, 3, 4, 5])
# -- CommitContributionSummary Create (1.1ms) INSERT INTO `contribution_summaries` (`counts`) VALUES ("\04P")
# ContributionSummary.last.counts
# => [1, 2, 3, 4, 5]
#
class CompressedIntegerArray < ActiveRecord::Type::Value
  COMPRESSION_FORMATS = {
    multi_value: 0,
    multi_sparse: 1,
    single_value: 2,
    single_one: 3,
    multi_sparse_offset: 4,
  }

  DATA_SIZES = {
    nibble: 0,
    byte: 1,
    smallint: 2,
    int: 3,
  }

  PACK_FORMATS = {
    nibble: "C",
    byte: "C",
    smallint: "S",
    int: "L",
  }

  UNPACK_OFFSETS = {
    nibble: 1,
    byte: 1,
    smallint: 2,
    int: 4,
  }

  # Public: generate an array of Integers by unpacking the specified binary string value.
  #
  # value - a packed binary string
  #
  # Returns nil if the specified value is nil, or an array of Integers otherwise.
  def deserialize(value)
    return nil if value.nil?

    GitHub.dogstats.distribution_time("compressed_integer_array.decompress.dist.time") do
      EncodedValue.new(value).decompressed
    end
  end

  # Public: generate a compressed binary string by packing the Integers in the specified
  # Array value.
  #
  # value - an array of integers
  #
  # Returns nil if the specified value is nil, or a packed string otherwise.
  def serialize(value)
    return nil if value.nil?

    GitHub.dogstats.distribution_time("compressed_integer_array.compress.dist.time") do
      DecodedValue.new(value).compressed
    end
  end

  # Public: whether the specified current/deserialized value is different from the specified
  # old/serialized value.
  #
  # Used by ActiveRecord to determine whether an attribute of this type has `changed?` and should
  # be updated in the database.
  #
  # Returns true if the values are different, false otherwise.
  def changed_in_place?(raw_old_value, current_value)
    deserialize(raw_old_value) != current_value
  end

  # Internal: A class for compressing an array of integers into a packed binary string.
  class DecodedValue
    attr_reader :compressed, :decompressed, :compression_format

    def initialize(value)
      @decompressed = value
      compress!
    end

    private

    def storage_size(values)
      case values.max
      when 0..15
        :nibble
      when 16..255
        :byte
      when 256..65535
        :smallint
      else
        :int
      end
    end

    def compress!
      if nonzero_indexes.size == 1
        if nonzero_values.first == 1
          # Optimized to store only the total count since we can infer the nonzero count, and
          # only the index of the nonzero value since we can infer the value. For the common
          # CommitContribution use case where a user has a single commit contribution for a
          # given repo/year.
          @compression_format = :single_one
          @compressed = compress(counts: [decompressed.size], data: nonzero_indexes, compression_format: :single_one)
        else
          # Optimized to store in sparse format with only the total count since we can infer
          # the nonzero count. For the common CommitContribution use case where a user has a
          # single day of commit contributions for a given repo/year, with more than one
          # commit on that day.
          @compression_format = :single_value
          @compressed = compress(counts: [decompressed.size], data: nonzero_data, compression_format: :single_value)
        end
      else
        # Optimized to try both full and sparse formats and use the one with the smaller
        # bytesize. Sparse format can be more efficient when more than half of the values are
        # zero, in which case we can store only the indexes and values of nonzero elements.
        options = {
          multi_value: compress(counts: [decompressed.size], data: decompressed, compression_format: :multi_value),
        }
        if nonzero_indexes.size < (decompressed.size >> 1)
          options[:multi_sparse_offset] = compress(counts: [decompressed.size, nonzero_indexes.size], data: offset_nonzero_data, compression_format: :multi_sparse_offset)
          options[:multi_sparse] = compress(counts: [decompressed.size, nonzero_indexes.size], data: nonzero_data, compression_format: :multi_sparse)
        end

        @compression_format, @compressed = options.min_by { |_, c| c.bytesize }
        data_size = case @compression_format
        when :multi_value
          storage_size(decompressed)
        when :multi_sparse
          storage_size(nonzero_data)
        when :multi_sparse_offset
          storage_size(offset_nonzero_data)
        end
      end

      GitHub.dogstats.increment("compressed_integer_array.compress", tags: ["format:#{compression_format}", "data_size:#{data_size}"])
      GitHub.dogstats.distribution("compressed_integer_array.compress.bytesize", @compressed.bytesize, tags: ["format:#{compression_format}", "data_size:#{data_size}"])
      GitHub.dogstats.distribution("compressed_integer_array.compress.sparse_count", nonzero_indexes.size, tags: ["format:#{compression_format}", "data_size:#{data_size}"])

      self
    end

    def compress(counts:, data:, compression_format:)
      data_size = storage_size(data)
      data_pack_format = PACK_FORMATS[data_size]
      data_values = data_size == :nibble ? nibbles_to_bytes(data) : data

      count_size = storage_size(counts)
      count_pack_format = PACK_FORMATS[count_size]
      if counts.size == 1
        count_pack_size = 1
        count_values = counts
      elsif count_size == :nibble
        count_pack_size = 1
        count_values = nibbles_to_bytes(counts)
      else
        count_pack_size = 2
        count_values = counts
      end

      header_byte = (COMPRESSION_FORMATS[compression_format] << 4) | (DATA_SIZES[count_size] << 2) | DATA_SIZES[data_size]
      unpacked = [header_byte] + count_values + data_values
      pack_string = "C#{count_pack_format}#{count_pack_size}#{data_pack_format}*"
      unpacked.pack(pack_string)
    end

    def nonzero_data
      @nonzero_data ||= nonzero_indexes + nonzero_values
    end

    def offset_nonzero_data
      @offset_nonzero_data ||= offset_nonzero_indexes + nonzero_values
    end

    def offset_nonzero_indexes
      @offset_nonzero_indexes = ([0] + nonzero_indexes).each_cons(2).map { |a, b| b - a }
    end

    def nonzero_indexes
      @nonzero_indexes ||= decompressed.each_index.select { |i| decompressed[i] != 0 }
    end

    def nonzero_values
      @nonzero_values ||= nonzero_indexes.map { |i| decompressed[i] }
    end

    def nibbles_to_bytes(nibbles)
      nibbles.each_slice(2).map { |left, right| left << 4 | (right || 0) }
    end
  end

  # Internal: A class for decompressing a packed binary string into an array of integers.
  class EncodedValue
    attr_reader :compressed, :decompressed

    def initialize(value)
      @compressed = value
      decompress!
    end

    private

    def header
      @header ||= @compressed.unpack("C1").first
    end

    def compression_format
      compression_format_value = (header & 0x70) >> 4
      COMPRESSION_FORMATS.key(compression_format_value)
    end

    def data_size
      data_size_value = header & 0x03
      DATA_SIZES.key(data_size_value)
    end

    def count_size
      count_size_value = (header & 0x0C) >> 2
      DATA_SIZES.key(count_size_value)
    end

    def sparse_format?
      compression_format == :multi_sparse || compression_format == :multi_sparse_offset
    end

    def counts
      count_pack_format = PACK_FORMATS[count_size]

      if sparse_format?
        packed_size = count_size == :nibble ? 1 : 2
        unpacked_counts = @compressed.unpack("#{count_pack_format}#{packed_size}", offset: 1)
        unpacked_counts = bytes_to_nibbles(unpacked_counts, 2) if count_size == :nibble
        unpacked_counts
      else
        @compressed.unpack(count_pack_format, offset: 1)
      end
    end

    def data_offset
      count_bytesize = UNPACK_OFFSETS[count_size]
      count_bytesize *= 2 if sparse_format? && count_size != :nibble
      count_bytesize + 1
    end

    def decompress!
      total_count, sparse_count = counts
      data_pack_format = PACK_FORMATS[data_size]

      @decompressed =
        case compression_format
        when :multi_value
          unpacked = @compressed.unpack("#{data_pack_format}*", offset: data_offset)
          unpacked = bytes_to_nibbles(unpacked, total_count) if data_size == :nibble
          unpacked
        when :multi_sparse, :multi_sparse_offset
          unpacked = @compressed.unpack("#{data_pack_format}*", offset: data_offset)
          unpacked = bytes_to_nibbles(unpacked, sparse_count * 2) if data_size == :nibble
          indexes = unpacked.first(sparse_count)
          values = unpacked.last(sparse_count)

          # If the indexes are stored as offsets from the previous index, resolve those to
          # actual index values.
          if compression_format == :multi_sparse_offset
            indexes = indexes.each_with_object([]) do |offset, resolved|
              resolved << (resolved.last || 0) + offset
            end
          end

          Array.new(total_count, 0).tap do |unpacked|
            indexes.each_with_index do |index, i|
              unpacked[index] = values[i]
            end
          end
        when :single_value
          index, value = if data_size == :nibble
            unpacked = @compressed.unpack(data_pack_format, offset: data_offset)
            bytes_to_nibbles(unpacked, 2)
          else
            @compressed.unpack("#{data_pack_format}2", offset: data_offset)
          end

          Array.new(total_count, 0).fill(value, index, 1)
        when :single_one
          index = if data_size == :nibble
            unpacked = @compressed.unpack(data_pack_format, offset: data_offset)
            bytes_to_nibbles(unpacked, 1).first
          else
            @compressed.unpack(data_pack_format, offset: data_offset).first
          end

          Array.new(total_count, 0).fill(1, index, 1)
        end

      GitHub.dogstats.increment("compressed_integer_array.decompress", tags: ["format:#{compression_format}", "data_size:#{data_size}"])
      GitHub.dogstats.distribution("compressed_integer_array.decompress.bytesize", @compressed.bytesize, tags: ["format:#{compression_format}", "data_size:#{data_size}"])
      GitHub.dogstats.distribution("compressed_integer_array.decompress.sparse_count", indexes.size, tags: ["format:#{compression_format}", "data_size:#{data_size}"]) if sparse_format?

      self
    end

    # When an odd number of nibbles are converted to bytes, the last byte will be padded
    # with a 0 nibble; when converting back we need to drop the padded nibble at the end.
    def bytes_to_nibbles(bytes, count)
      bytes.flat_map { |byte| [byte >> 4, byte & 0xF] }.first(count)
    end
  end
end
