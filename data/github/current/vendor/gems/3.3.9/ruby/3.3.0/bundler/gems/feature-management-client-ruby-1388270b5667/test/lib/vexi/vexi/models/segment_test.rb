# frozen_string_literal: true
# typed: true

require "test_helper"

class SegmentTest < Minitest::Test

  describe "to_hash" do
    it "converts segment with actors hash to hash" do
      expected_hash = {
        "name" => "_test_flag",
        "actors" => {"User:1" => true, "Repository:10" => true},
      }

      segment = Vexi::Segment.new(
        "_test_flag",
        actors: Vexi::HashActorCollection.new({"User:1" => true, "Repository:10" => true}),
      )
      hash = segment.to_hash

      assert_equal expected_hash, hash
    end

    it "converts segment with actors array to hash" do
      expected_hash = {
        "name" => "_test_flag",
        "actors" => ["User:1", "Repository:10"],
      }

      segment = Vexi::Segment.new(
        "_test_flag",
        actors: Vexi::Adapters::ArrayActorCollection.new(["User:1", "Repository:10"]),
      )
      hash = segment.to_hash

      assert_equal expected_hash, hash
    end
  end

  describe "from_hash" do
    it "converts segment with actors hash from hash" do
      hash = {
        "name" => "_test_flag",
        "actors" => {"User:1" => true, "Repository:10" => true},
      }
      expected_segment = Vexi::Segment.new(
        "_test_flag",
        actors: Vexi::HashActorCollection.new({"User:1" => true, "Repository:10" => true}),
      )

      segment = Vexi::Segment.from_hash(hash)

      assert_equal expected_segment, segment
    end

    it "converts segment with actors array from hash" do
      hash = {
        "name" => "_test_flag",
        "actors" => ["User:1", "Repository:10"],
      }
      expected_segment = Vexi::Segment.new(
        "_test_flag",
        actors: Vexi::Adapters::ArrayActorCollection.new(["User:1", "Repository:10"]),
      )

      segment = Vexi::Segment.from_hash(hash)

      assert_equal expected_segment, segment
    end
  end

  describe "from_hash and to_hash" do
    it "ensure no data loss with conversions back and forth from an original segment" do
      original_segment = Vexi::Segment.new(
        "_test_flag",
        actors: Vexi::HashActorCollection.new({"User:1" => true, "Repository:10" => true}),
      )

      first_hash = original_segment.to_hash

      from_hash_segment = Vexi::Segment.from_hash(first_hash)

      second_hash = from_hash_segment.to_hash

      assert_equal original_segment, from_hash_segment
      assert_equal first_hash, second_hash
    end

    it "ensure no data loss with conversions back and forth from an original hash" do
      original_hash = {
        "name" => "_test_flag",
        "actors" => ["User:1", "Repository:10"],
      }

      first_segment = Vexi::Segment.from_hash(original_hash)

      second_hash = first_segment.to_hash

      second_segment = Vexi::Segment.from_hash(second_hash)

      assert_equal original_hash, second_hash
      assert_equal first_segment, second_segment
    end
  end
end
