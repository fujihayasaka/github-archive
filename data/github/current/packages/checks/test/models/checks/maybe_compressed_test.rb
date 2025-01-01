# typed: true
# frozen_string_literal: true

require "test_helper"

class Checks::MaybeCompressedTest < GitHub::TestCase
  include DogstatsTestHelpers

  setup do
    @maybe_compressed = Checks::MaybeCompressed.new(CheckRun, "summary")
    @tags = ["table:check_run", "column:summary"]
    @uncompressed = "foobar"
    @compressed = Zstd.compress(@uncompressed, 3)
  end

  context "is_compressed?" do
    test "returns false for empty data" do
      refute Checks::MaybeCompressed.is_compressed?(nil)
      refute Checks::MaybeCompressed.is_compressed?("")
    end

    test "returns false for non-compressed data" do
      refute Checks::MaybeCompressed.is_compressed?(@uncompressed)
      refute Checks::MaybeCompressed.is_compressed?(@uncompressed.bytes)
    end

    test "returns true for compressed data" do
      assert Checks::MaybeCompressed.is_compressed?(@compressed)
      assert Checks::MaybeCompressed.is_compressed?(@compressed.bytes)
    end
  end

  context "deserialize" do
    test "when value is nil, it returns nil" do
      assert_nil @maybe_compressed.deserialize(nil)
      assert_dogstats_distribution 0, "checks.maybe_compressed.deserialize.dist.time", tags: @tags
    end

    test "when value is present and uncompressed, it returns the decompressed value" do
      assert_equal @maybe_compressed.deserialize(@uncompressed), @uncompressed
      assert_dogstats_distribution 0, "checks.maybe_compressed.deserialize.dist.time", tags: @tags
    end

    test "when value is compressed, it returns the decompressed value" do
      assert_equal @maybe_compressed.deserialize(@compressed), @uncompressed
      assert_dogstats_distribution 1, "checks.maybe_compressed.deserialize.dist.time", tags: @tags
    end
  end

  context "serialize" do
    test "when value is nil, it returns nil" do
      assert_nil @maybe_compressed.serialize(nil)
      assert_dogstats_distribution 0, "checks.maybe_compressed.serialize.dist.time", tags: @tags
    end

    test "when value is not compressed, it returns the compressed version" do
      assert_equal @maybe_compressed.serialize(@uncompressed), @compressed
      assert_dogstats_distribution 1, "checks.maybe_compressed.serialize.dist.time", tags: @tags
      assert_dogstats_distribution_value(
        (@uncompressed.bytesize / @compressed.bytesize.to_f),
        "checks.maybe_compressed.compression_ratio",
        tags: @tags
      )
      assert_dogstats_distribution_value(
        (@uncompressed.bytesize - @compressed.bytesize),
        "checks.maybe_compressed.bytes_saved",
        tags: @tags
      )
    end

    test "when value is an empty string, it still returns the compressed version" do
      assert_equal @maybe_compressed.serialize(""), Zstd.compress("", 3)
      assert_dogstats_distribution 1, "checks.maybe_compressed.serialize.dist.time", tags: @tags
      assert_dogstats_distribution_value(
        0.0,
        "checks.maybe_compressed.compression_ratio",
        tags: @tags
      )
      assert_dogstats_distribution_value(
        ("".bytesize - Zstd.compress("", 3).bytesize),
        "checks.maybe_compressed.bytes_saved",
        tags: @tags
      )
    end
  end
end
