# typed: true
# frozen_string_literal: true

require "zstd-ruby"

# Public: An ActiveRecord type meant to be set as type for an attribute in a model.
# Once this type is set for a particular attribute, anytime the attribute is
# written to the database, it will be compressed and anytime it is read from
# the database, it will be uncompressed and UTF-8 encoded.
#
# Note: To be able to accurately tag our metrics, we need to pass the class and column that is being compressed.
#  Once we no longer need to collect metrics on these, we can stop requiring these arguments to be passed on initialization.
#
# Examples
#
#   class Issue < ApplicationRecord::Domain::Repositories
#
#     attribute :compressed_body, CompressedString.new('issue', 'body')
#
#   end
#
#   issue = Issue.create(compressed_body: 'foo')
#
#   issue.compressed_body
#   # => "foo"
#
#   issue.read_attribute(:compressed_body)
#   # => "x\xDAK\xCB\xCF\a\x00\x02\x82\x01E"

class CompressedString < ActiveRecord::Type::Binary
  def initialize(klass, column)
    super()

    @klass = klass.underscore
    @column = column
  end

  # Public: Decompress a compressed string.
  #
  # value  - The compressed String to be decompressed.
  #
  # Examples
  #
  #   deserialize("x\xDAK\xCB\xCF\a\x00\x02\x82\x01E")
  #   # => "foo"
  #
  # Returns the decompressed String UTF-8 encoded.
  def deserialize(value)
    value = super
    if value
      value = GitHub.dogstats.distribution_time("compressed_string.deserialize.dist.time", tags: ["table:#{klass}", "column:#{column}"]) { Zstd.decompress(value).force_encoding("UTF-8") }
    end
    value
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
  # value  - The String to be compressed.
  #
  # Examples
  #
  #   serialize('foo')
  #   # => ActiveModel::Type::Binary::Data:0x0000000123e3cbe0 @value="x\xDAK\xCB\xCF\a\x00\x02\x82\x01E"
  #
  # Returns an ActiveModel::Type::Binary::Data with the value set to the compressed value.
  def serialize(value)
    if value
      pre_compressed_bytesize = value.bytesize
      value = GitHub.dogstats.distribution_time("compressed_string.serialize.dist.time", tags: ["table:#{klass}", "column:#{column}"]) { Zstd.compress(value, 3) }
      GitHub.dogstats.distribution("compressed_string.compression_ratio", (pre_compressed_bytesize / value.bytesize.to_f), tags: ["table:#{klass}", "column:#{column}"])
      GitHub.dogstats.distribution("compressed_string.bytes_saved", pre_compressed_bytesize - value.bytesize, tags: ["table:#{klass}", "column:#{column}"])
    end
    super(value)
  end

  private

  attr_reader :klass, :column
end
