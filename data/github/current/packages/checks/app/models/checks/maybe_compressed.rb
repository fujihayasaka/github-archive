# typed: true
# frozen_string_literal: true

require "zstd-ruby"

# Public: An ActiveRecord type meant to be set as type for an attribute in a model.
# Once this type is set for a particular attribute, anytime the attribute is
# written to the database (with the feature flag enable), it will be compressed
# and anytime it is read from the database, it will be uncompressed.
#
# This is heavily based on CompressedBinary and CompressedString models in packages/substrate/app/models/
# Major difference is that this supports reading both compressed (and non-compressed) by peeking at zstd magic.
#
#
# Examples
#
#   class CheckRun < ApplicationRecord::Domain::RepositoriesActionsChecks
#
#     attribute :summary, Checks::MaybeCompressed.new(self, :summary)
#
#   end
#
#   cr = CheckRun.create(summary: 'foo')
#
#   cr.summary
#   # => "foo"
#
#   cr.read_attribute_before_type_cast(field).to_s
#   # => "(\xB5/\xFD \x03\x19\x00\x00foo"

class Checks::MaybeCompressed < ActiveRecord::Type::Binary
  # This is the magic number (0xFD2FB528 in little-endian) that is used to identify the start of a Zstandard frame.
  # Source: https://github.com/facebook/zstd/blob/dev/doc/zstd_compression_format.md#zstandard-frames
  ZSTD_MAGIC = [0x28, 0xB5, 0x2F, 0xFD].freeze

  attr_reader :table, :column

  # Public: Determines if a value is compressed or not
  #
  # value - The compressed String (or Array of bytes) to be checked.
  #
  # Examples
  #
  #   Checks::MaybeCompressed.is_compressed?("(\xB5/\xFD \x03\x19\x00\x00foo")
  #   # => true
  #
  #   Checks::MaybeCompressed.is_compressed?([40, 181, 47, 253, 32, 3, 25, 0, 0, 102, 111, 111])
  #   # => true
  #
  #   Checks::MaybeCompressed.is_compressed?("foo")
  #   # => false
  #
  # Returns a boolean denoting if the input is compressed or not.
  def self.is_compressed?(value)
    return false unless value.present?

    if value.is_a?(String)
      value = value.bytes
    end

    value.first(4) == ZSTD_MAGIC
  end

  def initialize(klass, column)
    super()

    @table = klass.name.underscore
    @column = column
  end

  # Public: Decompress a compressed String, or returns the original if not compressed. Always forces UTF8 encoding.
  #
  # value - The compressed String to be decompressed.
  #
  # Examples
  #
  #   deserialize("(\xB5/\xFD \x03\x19\x00\x00foo")
  #   # => "foo"
  #
  # Returns the decompressed String.
  def deserialize(value)
    value = super
    if self.class.is_compressed?(value)
      value = GitHub.dogstats.distribution_time("checks.maybe_compressed.deserialize.dist.time", tags: stats_tags) { Zstd.decompress(value) }
    end

    StringFromBinary.new.deserialize(value)
  end

  def cast(value)
    if value.is_a?(Data)
      value.to_s
    else
      value
    end
  end

  # Public: Compress a string.
  #
  # value - The String to be compressed.
  #
  # Examples
  #
  #   serialize('foo')
  #   # => ActiveModel::Type::Binary::Data:0x0000000123e3cbe0 @value="(\xB5/\xFD \x03\x19\x00\x00foo"
  #
  # Returns an ActiveModel::Type::Binary::Data with the value set to the compressed value.
  def serialize(value)
    if value
      pre_compressed_bytesize = value.bytesize
      value = GitHub.dogstats.distribution_time("checks.maybe_compressed.serialize.dist.time", tags: stats_tags) { Zstd.compress(value, 3) }
      GitHub.dogstats.distribution("checks.maybe_compressed.compression_ratio", (pre_compressed_bytesize / value.bytesize.to_f), tags: stats_tags)
      GitHub.dogstats.distribution("checks.maybe_compressed.bytes_saved", pre_compressed_bytesize - value.bytesize, tags: stats_tags)
    end
    super(value)
  end

  private

  def stats_tags
    ["table:#{table}", "column:#{column}"]
  end
end
