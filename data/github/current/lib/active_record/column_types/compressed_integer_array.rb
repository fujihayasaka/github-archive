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
# where there is only one nonzero element in the array; and for cases where the array contains
# values for each day in a year (365 or 366). This column format works well for use cases where
# the values in the array don't need to be queried and tend to be very small and can be packed
# as bytes or nibbles. Such use cases include commit contributions, where a large majority of
# users contribute fewer than 16 commits per day/repo.
#
# Header byte format:
#
# bit 87654321
#     1xxxxxxx - when set the array represents daily values for one year, either 365 values or 366 if the
#                leap year bit is set; so total count doesn't need to be encoded in the packed string
#     x111xxxx - compression format
#     xxxx11xx - when the year bit is not set, size of array count(s) - total count and optional nonzero count
#                when the year bit is set, the lower bit indicates a leap year (366 values) and the upper bit
#                indicates that the first index value is > 256 (used only for index-based formats)
#     xxxxxx11 - data size
#
# Supported values for compression format are:
#
# 000 - multi_value: one count value (N=total count) followed by N values
# 001 - multi_sparse: (deprecated) two count values (total count and N=nonzero count) followed by N indexes and N values
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
# Y||||||| ^^CD^^UN ^^E1^^E2 ^^E3^^E4 ^^E5^^E6 ^^E7^^E8 ^^E9^^UN
#   CF||||
#     CS||
#       DS
#
#  Y: Yearly format,       0 = 0x00 = not yearly, total count will be encoded in the packed string
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
# Y||||||| ^^TC^^NC ^^I1^^I2 ^^I3^^I4 ^^E1^^E2 ^^E3^^E4
#   CF||||
#     CS||
#       DS
#
#  Y: Yearly format,       0 = 0x00 = not yearly, total count will be encoded in the packed string
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
# Example format with a single nonzero value - eg. Array.new(365, 0).fill(42, 180, 1), stored as a 3-byte string:
#
# > CompressedIntegerArray.new.serialize(Array.new(365, 0).fill(42, 180, 1)).bytes.map { |b| "0x%02x" % b }.join(" ")
# => "0xa1 0xb4 0x2a"
#
# Header   Index    Value
# 0xa1     0xb4     0x2a
# 10100001 10110100 00101010
# Y||||||| ^^^^^^I1 ^^^^^^E1
#   CF||||
#     H|||
#      L||
#       DS
#
#  Y: Yearly format,        0 = 0x00 = yearly, total count is 365 (or 366)
# CF: compression format, 010 = 0x02 = :single_value
#  H: High index,           0 = 0x00 = first index is not > 256
#  L: Leap year,            0 = 0x00 = not a leap year, total count is 365
# DS: data size,           01 = 0x01 = byte/8 bits
# I1: index 1,       10110100 = 0xb4 = 180
# E1: element 1,     00101010 = 0x2a = 42
#
#
# Example format with a single nonzero value of 1 - eg. Array.new(365, 0).fill(1, 180, 1), stored as a 2-byte string:
#
# > CompressedIntegerArray.new.serialize(Array.new(365, 0).fill(1, 180, 1)).bytes.map { |b| "0x%02x" % b }.join(" ")
# => "0xb1 0xb4"
#
# Header   Index
# 0xb1     0xb4
# 10110001 10110100
# Y||||||| ^^^^^^I1
#   CF||||
#     H|||
#      L||
#       DS
#
#  Y: Yearly format,        0 = 0x00 = yearly, total count is 365 (or 366)
# CF: compression format, 011 = 0x03 = :single_one
#  H: High index,           0 = 0x00 = first index is not > 256
#  L: Leap year,            0 = 0x00 = not a leap year, total count is 365
# DS: data size,           01 = 0x01 = byte/8 bits
# I1: index 1,       10110100 = 0xb4 = 180
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
class CompressedIntegerArray < ActiveRecord::Type::Binary
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

  # Public: A class for storing an unpacked Integer Array with annotations containing metadata
  # about the array contents.
  class AnnotatedArray < Array
    attr_writer :first_nonzero_index, :last_nonzero_index

    def self.from(other)
      new.replace(other)
    end

    def []=(index, value)
      super

      if value && value > 0
        # Setting a nonzero value at a different index may replace the first/last nonzero index
        @first_nonzero_index = index if first_nonzero_index.nil? || index < first_nonzero_index
        @last_nonzero_index = index if last_nonzero_index.nil? || index > last_nonzero_index
      else
        # Unsetting the value of the current first/last nonzero index means we need to find a new one.
        @first_nonzero_index = index { |v| v && v > 0 } if index == first_nonzero_index
        @last_nonzero_index = rindex { |v| v && v > 0 } if index == last_nonzero_index
      end
    end

    def first_nonzero_index
      return @first_nonzero_index if defined?(@first_nonzero_index)
      @first_nonzero_index = index { |v| v && v > 0 }
    end

    def last_nonzero_index
      return @last_nonzero_index if defined?(@last_nonzero_index)
      @last_nonzero_index = rindex { |v| v && v > 0 }
    end
  end

  def type
    :compressed_integer_array
  end

  # Public: generate an array of Integers by unpacking the specified binary string value.
  #
  # value - a packed binary string
  #
  # Returns nil if the specified value is nil, or an array of Integers otherwise.
  def deserialize(value)
    value = super
    return nil if value.nil?

    GitHub.dogstats.distribution_time("compressed_integer_array.decompress.dist.time") do
      EncodedValue.new(value).decompressed
    end
  end

  def cast(value)
    if value.is_a?(Data)
      value.to_s
    else
      value
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
      super(DecodedValue.new(value).compressed)
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
        end

        @compression_format, @compressed = options.min_by { |_, c| c.bytesize }
        data_size = case @compression_format
        when :multi_value
          storage_size(decompressed)
        when :multi_sparse_offset
          storage_size(offset_nonzero_data)
        end
      end

      GitHub.dogstats.increment("compressed_integer_array.compress", tags: ["format:#{compression_format}", "data_size:#{data_size}", "yearly:#{yearly?}"])
      GitHub.dogstats.distribution("compressed_integer_array.compress.bytesize", @compressed.bytesize, tags: ["format:#{compression_format}", "data_size:#{data_size}", "yearly:#{yearly?}"])
      GitHub.dogstats.distribution("compressed_integer_array.compress.sparse_count", nonzero_indexes.size, tags: ["format:#{compression_format}", "data_size:#{data_size}", "yearly:#{yearly?}"])

      self
    end

    def compress(counts:, data:, compression_format:)
      data_size = storage_size(data)
      data_pack_format = PACK_FORMATS[data_size]
      data_values = data_size == :nibble ? nibbles_to_bytes(data) : data

      if yearly?
        if compression_format == :multi_sparse_offset
          # :multi_sparse_offset compression only needs to store the nonzero value count, and
          # it will always fit in a byte when encoding a yearly array due to the high index
          # bit.
          count_values = [counts[1]]
          count_pack_format = PACK_FORMATS[:byte]
          count_pack_size = 1
        else
          # No counts are stored in other compression formats for yearly arrays. The format/size
          # will interpolate to empty strings in the pack string.
          count_values = []
          count_pack_format = nil
          count_pack_size = nil

          # :single compression formats that store index values can always fit them in a byte
          # due the limit on total count combined with the high index bit.
          if high_index? && [:single_one, :single_value].include?(compression_format)
            # Use a copy of the source data because we're changing the first byte.
            data_values = data_values.dup
            data_values[0] &= 0xFF
            if compression_format == :single_one
              data_size = :byte
            elsif compression_format == :single_value
              data_size = storage_size(data_values)
              data_values = nibbles_to_bytes(data_values) if data_size == :nibble
            end
            data_pack_format = PACK_FORMATS[data_size]
          end
        end
      else
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
      end

      header_byte = yearly_bit | compression_header_bits(compression_format) | count_header_bits(count_size) | data_header_bits(data_size)
      unpacked = [header_byte] + count_values + data_values
      pack_string = "C#{count_pack_format}#{count_pack_size}#{data_pack_format}*"
      unpacked.pack(pack_string)
    end

    # Whether the array size is 365 or 366, indicating a daily value for each day of the year.
    #
    # Returns a Boolean.
    def yearly?
      decompressed.size == 365 || decompressed.size == 366
    end

    # Whether the array size is 366, indicating a daily value for each day of a leap year.
    #
    # Returns a Boolean.
    def leap_year?
      decompressed.size == 366
    end

    # The value to set in the header to indicate whether the array represents daily values for
    # one year.
    #
    # Returns an Integer.
    def yearly_bit
      yearly? ? 0x80 : 0
    end

    # The value to set in the header to indicate the compression format used.
    #
    # Returns an Integer.
    def compression_header_bits(compression_format)
      COMPRESSION_FORMATS[compression_format] << 4
    end

    # Whether the first index value in a yearly array is > 256, indicating we should encode as a byte and decode as
    # a smallint.
    #
    # Returns a Boolean.
    def high_index?
      return false unless yearly?

      nonzero_indexes.first > 255
    end

    # The value to set in the header to indicate either:
    # - for yearly arrays, whether the year is a leap year and whether the first index value is > 255
    # - for non-yearly arrays, the size of the count values
    #
    # Returns an Integer.
    def count_header_bits(count_size)
      if yearly?
        leap_year_bit = leap_year? ? 0x01 : 0
        high_index_bit = high_index? ? 0x02 : 0
        (leap_year_bit | high_index_bit) << 2
      else
        DATA_SIZES[count_size] << 2
      end
    end

    # The value to set in the header to indicate the data size used to store array values.
    #
    # Returns an Integer.
    def data_header_bits(data_size)
      DATA_SIZES[data_size]
    end

    # The combined nonzero indexes and nonzero values in the array.
    #
    # Returns an Array of Integers.
    def nonzero_data
      @nonzero_data ||= nonzero_indexes + nonzero_values
    end

    # The combined nonzero index offsets and nonzero values in the array.
    #
    # Returns an Array of Integers.
    def offset_nonzero_data
      @offset_nonzero_data ||= offset_nonzero_indexes + nonzero_values
    end

    # The indexes of nonzero values in the array, represented as offsets from the previous index.
    # Offsets are generally smaller numbers which allow us to use a smaller data size to store
    # index values.
    #
    # Returns an Array of Integers.
    def offset_nonzero_indexes
      @offset_nonzero_indexes ||= begin
        base_index = high_index? ? 256 : 0
        ([base_index] + nonzero_indexes).each_cons(2).map { |a, b| b - a }
      end
    end

    # The indexes of nonzero values in the array.
    #
    # Returns an Array of Integers.
    def nonzero_indexes
      @nonzero_indexes ||= decompressed.each_index.select { |i| decompressed[i] != 0 }
    end

    # The nonzero values in the array.
    #
    # Returns an Array of Integers.
    def nonzero_values
      @nonzero_values ||= nonzero_indexes.map { |i| decompressed[i] }
    end

    # For cases where values are all < 16, combine pairs of 4-bit nibbles into 8-bit bytes.
    #
    # Returns an Array of Integers.
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

    # Whether the array was compressed using yearly format, so we can infer the total count represents
    # one value for each day of the year.
    #
    # Returns a Boolean.
    def yearly?
      (header & 0x80) == 0x80
    end

    # Whether an array compressed using yearly format represents a leap year
    #
    # Returns a Boolean.
    def leap_year?
      return false unless yearly?

      count_header_bits = (header & 0x0C) >> 2
      (count_header_bits & 0x01) == 0x01
    end

    # For formats that store indexes, the base relative to the first index. For yearly arrays,
    # a header bit may indicate that the first index is > 256, and using this as a base allows
    # us to store the relative index value as a byte instead of a smallint.
    #
    # Returns an Integer.
    def index_base
      return 0 unless yearly?

      count_header_bits = (header & 0x0C) >> 2
      (count_header_bits & 0x02) == 0x02 ? 256 : 0
    end

    # The compression format used to store the array.
    #
    # Returns a Symbol representing the compression format.
    def compression_format
      compression_format_value = (header & 0x70) >> 4
      COMPRESSION_FORMATS.key(compression_format_value)
    end

    # The data size that was used to store array values. This is based on the maximum value in
    # the array:
    #
    # - if all values are less than 16 they are stored as 4-bit nibbles
    # - if all values are between 16 and 255 they are stored as 8-bit bytes
    # - if all values are between 256 and 65535 they are stored as 16-bit smallints
    # - if any value is greater than 65535 they are stored as 32-bit ints
    #
    # Returns a Symbol representing the data size.
    def data_size
      data_size_value = header & 0x03
      DATA_SIZES.key(data_size_value)
    end

    # For formats that store one or more count values, the data size used to store the count(s).
    #
    # Returns a Symbol representing the data size, or nil if the format does not store count values.
    def count_size
      if yearly?
        if compression_format == :multi_sparse_offset
          # Sparse format stores the nonzero count, which is always stored as a byte for yearly
          # arrays because there are fewer than 256 nonzero values.
          :byte
        else
          # Other yearly formats do not store count values since the total count is implied.
          nil
        end
        compression_format == :multi_sparse_offset ? :byte : nil
      else
        count_size_value = (header & 0x0C) >> 2
        DATA_SIZES.key(count_size_value)
      end
    end

    # Whether the array was compressed using a sparse format, where only nonzero indexes and
    # values are stored.
    #
    # Returns a Boolean.
    def sparse_format?
      compression_format == :multi_sparse || compression_format == :multi_sparse_offset
    end

    # The total count and optional nonzero count used to store the array values.
    #
    # Returns an Array of one or two Integers.
    def counts
      count_pack_format = PACK_FORMATS[count_size]

      if yearly?
        # The total count is inferred when using yearly compression
        counts = leap_year? ? [366] : [365]

        # :multi_sparse_offset format stores only the nonzero count when using yearly compression,
        # and it is always stored as a byte.
        if compression_format == :multi_sparse_offset
          counts += @compressed.unpack("#{count_pack_format}", offset: 1)
        end

        counts
      elsif sparse_format?
        packed_size = count_size == :nibble ? 1 : 2
        unpacked_counts = @compressed.unpack("#{count_pack_format}#{packed_size}", offset: 1)
        unpacked_counts = bytes_to_nibbles(unpacked_counts, 2) if count_size == :nibble
        unpacked_counts
      else
        @compressed.unpack(count_pack_format, offset: 1)
      end
    end

    # The byte offset in the packed string to where array values start. This skips over the header
    # byte, and any count bytes if they are present.
    #
    # Returns an Integer.
    def data_offset
      if yearly?
        # Skip over the extra nonzero count byte when using yearly compression with :multi_sparse_offset,
        # other yearly formats do not store count values so we only need to skip over the header byte.
        compression_format == :multi_sparse_offset ? 2 : 1
      else
        # Non-yearly formats encode the count size in the header; we need to skip over the header byte,
        # the bytes representing the total count, and for sparse formats the bytes representing the
        # nonzero count. When both counts are stored as :nibbles, they are combined into a single byte.
        count_bytesize = UNPACK_OFFSETS[count_size]
        count_bytesize *= 2 if sparse_format? && count_size != :nibble
        count_bytesize + 1
      end
    end

    def decompress!
      total_count, sparse_count = counts
      data_pack_format = PACK_FORMATS[data_size]

      @decompressed =
        case compression_format
        when :multi_value
          unpacked = @compressed.unpack("#{data_pack_format}*", offset: data_offset)
          unpacked = bytes_to_nibbles(unpacked, total_count) if data_size == :nibble
          unpacked = AnnotatedArray.from(unpacked)
          unpacked.first_nonzero_index = unpacked.index { |v| v > 0 }
          unpacked.last_nonzero_index = unpacked.rindex { |v| v > 0 }
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
              resolved << (resolved.last || index_base) + offset
            end
          end

          AnnotatedArray.new(total_count, 0).tap do |unpacked|
            indexes.each_with_index do |index, i|
              unpacked[index] = values[i]
            end

            unpacked.first_nonzero_index = indexes.first
            unpacked.last_nonzero_index = indexes.last
          end
        when :single_value
          index, value = if data_size == :nibble
            unpacked = @compressed.unpack(data_pack_format, offset: data_offset)
            bytes_to_nibbles(unpacked, 2)
          else
            @compressed.unpack("#{data_pack_format}2", offset: data_offset)
          end

          based_index = index + index_base
          AnnotatedArray.new(total_count, 0).fill(value, based_index, 1).tap do |unpacked|
            unpacked.first_nonzero_index = based_index
            unpacked.last_nonzero_index = based_index
          end
        when :single_one
          index = if data_size == :nibble
            unpacked = @compressed.unpack(data_pack_format, offset: data_offset)
            bytes_to_nibbles(unpacked, 1).first
          else
            @compressed.unpack(data_pack_format, offset: data_offset).first
          end

          based_index = index + index_base
          AnnotatedArray.new(total_count, 0).fill(1, based_index, 1).tap do |unpacked|
            unpacked.first_nonzero_index = based_index
            unpacked.last_nonzero_index = based_index
          end
        end

      GitHub.dogstats.increment("compressed_integer_array.decompress", tags: ["format:#{compression_format}", "data_size:#{data_size}", "yearly:#{yearly?}"])
      GitHub.dogstats.distribution("compressed_integer_array.decompress.bytesize", @compressed.bytesize, tags: ["format:#{compression_format}", "data_size:#{data_size}", "yearly:#{yearly?}"])
      GitHub.dogstats.distribution("compressed_integer_array.decompress.sparse_count", indexes.size, tags: ["format:#{compression_format}", "data_size:#{data_size}", "yearly:#{yearly?}"]) if sparse_format?

      self
    end

    # When an odd number of nibbles are converted to bytes, the last byte will be padded
    # with a 0 nibble; when converting back we need to drop the padded nibble at the end.
    def bytes_to_nibbles(bytes, count)
      bytes.flat_map { |byte| [byte >> 4, byte & 0xF] }.first(count)
    end
  end
end
