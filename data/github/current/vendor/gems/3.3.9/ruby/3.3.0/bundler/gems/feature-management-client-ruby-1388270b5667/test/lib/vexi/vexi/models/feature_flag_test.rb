# frozen_string_literal: true
# typed: true

require "test_helper"

class FeatureFlagTest < Minitest::Test

  describe "to_hash" do
    it "converts disabled feature flag to hash" do
      expected_hash = {
        "name" => "test_flag",
        "boolean_gate" => false,
        "percentage_of_actors" => 0.0,
        "percentage_of_calls" => 0.0,
        "custom_gates" => [],
        "actors" => {},
        "segments" => [],
      }

      ff = Vexi::FeatureFlag.create_boolean_feature_flag("test_flag", false)
      hash = ff.to_hash

      assert_equal expected_hash, hash
    end

    it "converts enabled feature flag to hash" do
      expected_hash = {
        "name" => "test_flag",
        "boolean_gate" => true,
        "percentage_of_actors" => 0.0,
        "percentage_of_calls" => 0.0,
        "custom_gates" => [],
        "actors" => {},
        "segments" => [],
      }

      ff = Vexi::FeatureFlag.create_boolean_feature_flag("test_flag", true)
      hash = ff.to_hash

      assert_equal expected_hash, hash
    end

    it "converts feature flag with percentage_of_actors to hash" do
      expected_hash = {
        "name" => "test_flag",
        "boolean_gate" => false,
        "percentage_of_actors" => 50.0,
        "percentage_of_calls" => 0.0,
        "custom_gates" => [],
        "actors" => {},
        "segments" => [],
      }

      ff = Vexi::FeatureFlag.new(
        "test_flag",
        boolean_gate: false,
        percentage_of_actors: 50.0,
        percentage_of_calls: 0.0,
        segments: [],
        custom_gates: [],
        actors: Vexi::HashActorCollection.new({})
      )
      hash = ff.to_hash

      assert_equal expected_hash, hash
    end

    it "converts feature flag with percentage_of_calls to hash" do
      expected_hash = {
        "name" => "test_flag",
        "boolean_gate" => false,
        "percentage_of_actors" => 0.0,
        "percentage_of_calls" => 20.0,
        "custom_gates" => [],
        "actors" => {},
        "segments" => [],
      }

      ff = Vexi::FeatureFlag.new(
        "test_flag",
        boolean_gate: false,
        percentage_of_actors: 0.0,
        percentage_of_calls: 20.0,
        segments: [],
        custom_gates: [],
        actors: Vexi::HashActorCollection.new({})
      )
      hash = ff.to_hash

      assert_equal expected_hash, hash
    end

    it "converts feature flag with custom_gates to hash" do
      expected_hash = {
        "name" => "test_flag",
        "boolean_gate" => false,
        "percentage_of_actors" => 0.0,
        "percentage_of_calls" => 0.0,
        "custom_gates" => ["gate1", "gate2"],
        "actors" => {},
        "segments" => [],
      }

      ff = Vexi::FeatureFlag.new(
        "test_flag",
        boolean_gate: false,
        percentage_of_actors: 0.0,
        percentage_of_calls: 0.0,
        segments: [],
        custom_gates: ["gate1", "gate2"],
        actors: Vexi::HashActorCollection.new({})
      )
      hash = ff.to_hash

      assert_equal expected_hash, hash
    end

    it "converts feature flag with actors hash to hash" do
      expected_hash = {
        "name" => "test_flag",
        "boolean_gate" => false,
        "percentage_of_actors" => 0.0,
        "percentage_of_calls" => 0.0,
        "custom_gates" => [],
        "actors" => {"User:1" => true, "Repository:10" => true},
        "segments" => [],
      }

      ff = Vexi::FeatureFlag.new(
        "test_flag",
        boolean_gate: false,
        percentage_of_actors: 0.0,
        percentage_of_calls: 0.0,
        segments: [],
        custom_gates: [],
        actors: Vexi::HashActorCollection.new({"User:1" => true, "Repository:10" => true})
      )
      hash = ff.to_hash

      assert_equal expected_hash, hash
    end

    it "converts feature flag with actors array to hash" do
      expected_hash = {
        "name" => "test_flag",
        "boolean_gate" => false,
        "percentage_of_actors" => 0.0,
        "percentage_of_calls" => 0.0,
        "custom_gates" => [],
        "actors" => ["User:1", "Repository:10"],
        "segments" => [],
      }

      ff = Vexi::FeatureFlag.new(
        "test_flag",
        boolean_gate: false,
        percentage_of_actors: 0.0,
        percentage_of_calls: 0.0,
        segments: [],
        custom_gates: [],
        actors: Vexi::Adapters::ArrayActorCollection.new(["User:1", "Repository:10"]),
      )
      hash = ff.to_hash

      assert_equal expected_hash, hash
    end

    it "converts feature flag with segments to hash" do
      expected_hash = {
        "name" => "test_flag",
        "boolean_gate" => false,
        "percentage_of_actors" => 0.0,
        "percentage_of_calls" => 0.0,
        "custom_gates" => [],
        "actors" => {},
        "segments" => ["segment1", "segment2"],
      }

      ff = Vexi::FeatureFlag.new(
        "test_flag",
        boolean_gate: false,
        percentage_of_actors: 0.0,
        percentage_of_calls: 0.0,
        segments: ["segment1", "segment2"],
        custom_gates: [],
        actors: Vexi::HashActorCollection.new({})
      )
      hash = ff.to_hash

      assert_equal expected_hash, hash
    end
  end

  describe "from_hash" do
    it "converts disabled feature flag from hash" do
      hash = {
        "name" => "test_flag",
        "boolean_gate" => false,
        "percentage_of_actors" => 0.0,
        "percentage_of_calls" => 0.0,
        "custom_gates" => [],
        "actors" => {},
        "segments" => [],
      }
      expected_ff = Vexi::FeatureFlag.create_boolean_feature_flag("test_flag", false)

      ff = Vexi::FeatureFlag.from_hash(hash)

      assert_equal expected_ff, ff
    end

    it "converts enabled feature flag from hash" do
      hash = {
        "name" => "test_flag",
        "boolean_gate" => true,
        "percentage_of_actors" => 0.0,
        "percentage_of_calls" => 0.0,
        "custom_gates" => [],
        "actors" => {},
        "segments" => [],
      }
      expected_ff = Vexi::FeatureFlag.create_boolean_feature_flag("test_flag", true)

      ff = Vexi::FeatureFlag.from_hash(hash)

      assert_equal expected_ff, ff
    end

    it "converts feature flag with percentage_of_actors from hash" do
      hash = {
        "name" => "test_flag",
        "boolean_gate" => false,
        "percentage_of_actors" => 50.0,
        "percentage_of_calls" => 0.0,
        "custom_gates" => [],
        "actors" => {},
        "segments" => [],
      }
      expected_ff = Vexi::FeatureFlag.new(
        "test_flag",
        boolean_gate: false,
        percentage_of_actors: 50.0,
        percentage_of_calls: 0.0,
        segments: [],
        custom_gates: [],
        actors: Vexi::HashActorCollection.new({})
      )

      ff = Vexi::FeatureFlag.from_hash(hash)

      assert_equal expected_ff, ff
    end

    it "converts feature flag with percentage_of_calls from hash" do
      hash = {
        "name" => "test_flag",
        "boolean_gate" => false,
        "percentage_of_actors" => 0.0,
        "percentage_of_calls" => 20.0,
        "custom_gates" => [],
        "actors" => {},
        "segments" => [],
      }
      expected_ff = Vexi::FeatureFlag.new(
        "test_flag",
        boolean_gate: false,
        percentage_of_actors: 0.0,
        percentage_of_calls: 20.0,
        segments: [],
        custom_gates: [],
        actors: Vexi::HashActorCollection.new({})
      )

      ff = Vexi::FeatureFlag.from_hash(hash)

      assert_equal expected_ff, ff
    end

    it "converts feature flag with custom_gates from hash" do
      hash = {
        "name" => "test_flag",
        "boolean_gate" => false,
        "percentage_of_actors" => 0.0,
        "percentage_of_calls" => 0.0,
        "custom_gates" => ["gate1", "gate2"],
        "actors" => {},
        "segments" => [],
      }
      expected_ff = Vexi::FeatureFlag.new(
        "test_flag",
        boolean_gate: false,
        percentage_of_actors: 0.0,
        percentage_of_calls: 0.0,
        segments: [],
        custom_gates: ["gate1", "gate2"],
        actors: Vexi::HashActorCollection.new({})
      )

      ff = Vexi::FeatureFlag.from_hash(hash)

      assert_equal expected_ff, ff
    end

    it "converts feature flag with actors hash from hash" do
      hash = {
        "name" => "test_flag",
        "boolean_gate" => false,
        "percentage_of_actors" => 0.0,
        "percentage_of_calls" => 0.0,
        "custom_gates" => [],
        "actors" => {"User:1" => true, "Repository:10" => true},
        "segments" => [],
      }
      expected_ff = Vexi::FeatureFlag.new(
        "test_flag",
        boolean_gate: false,
        percentage_of_actors: 0.0,
        percentage_of_calls: 0.0,
        segments: [],
        custom_gates: [],
        actors: Vexi::HashActorCollection.new({"User:1" => true, "Repository:10" => true})
      )

      ff = Vexi::FeatureFlag.from_hash(hash)

      assert_equal expected_ff, ff
    end

    it "converts feature flag with actors array from hash" do
      hash = {
        "name" => "test_flag",
        "boolean_gate" => false,
        "percentage_of_actors" => 0.0,
        "percentage_of_calls" => 0.0,
        "custom_gates" => [],
        "actors" => ["User:1", "Repository:10"],
        "segments" => [],
      }
      expected_ff = Vexi::FeatureFlag.new(
        "test_flag",
        boolean_gate: false,
        percentage_of_actors: 0.0,
        percentage_of_calls: 0.0,
        segments: [],
        custom_gates: [],
        actors: Vexi::Adapters::ArrayActorCollection.new(["User:1", "Repository:10"]),
      )

      ff = Vexi::FeatureFlag.from_hash(hash)

      assert_equal expected_ff, ff
    end

    it "converts feature flag with segments from hash" do
      hash = {
        "name" => "test_flag",
        "boolean_gate" => false,
        "percentage_of_actors" => 0.0,
        "percentage_of_calls" => 0.0,
        "custom_gates" => [],
        "actors" => {},
        "segments" => ["segment1", "segment2"],
      }
      expected_ff = Vexi::FeatureFlag.new(
        "test_flag",
        boolean_gate: false,
        percentage_of_actors: 0.0,
        percentage_of_calls: 0.0,
        segments: ["segment1", "segment2"],
        custom_gates: [],
        actors: Vexi::HashActorCollection.new({})
      )

      ff = Vexi::FeatureFlag.from_hash(hash)

      assert_equal expected_ff, ff
    end
  end

  describe "from_hash and to_hash" do
    it "ensure no data loss with conversions back and forth from an original feature flag" do
      original_ff = Vexi::FeatureFlag.new(
        "test_flag",
        boolean_gate: false,
        percentage_of_actors: 33.2,
        percentage_of_calls: 12.8,
        segments: ["segment1", "segment2"],
        custom_gates: ["gate1", "gate2"],
        actors: Vexi::HashActorCollection.new({"User:1" => true, "Repository:10" => true})
      )

      first_hash = original_ff.to_hash

      from_hash_ff = Vexi::FeatureFlag.from_hash(first_hash)

      second_hash = from_hash_ff.to_hash

      assert_equal original_ff, from_hash_ff
      assert_equal first_hash, second_hash
    end

    it "ensure no data loss with conversions back and forth from an original feature flag with boolean_gate true" do
      original_ff = Vexi::FeatureFlag.new(
        "test_flag",
        boolean_gate: true,
        percentage_of_actors: 33.2,
        percentage_of_calls: 12.8,
        segments: ["segment1", "segment2"],
        custom_gates: ["gate1", "gate2"],
        actors: Vexi::HashActorCollection.new({"User:1" => true, "Repository:10" => true})
      )

      first_hash = original_ff.to_hash

      from_hash_ff = Vexi::FeatureFlag.from_hash(first_hash)

      second_hash = from_hash_ff.to_hash

      assert_equal original_ff, from_hash_ff
      assert_equal first_hash, second_hash
    end

    it "ensure no data loss with conversions back and forth from an original hash" do
      original_hash = {
        "name" => "test_flag",
        "boolean_gate" => false,
        "percentage_of_actors" => 33.2,
        "percentage_of_calls" => 12.8,
        "custom_gates" => ["gate1", "gate2"],
        "actors" => ["User:1", "Repository:10"],
        "segments" => ["segment1", "segment2"],
      }

      first_ff = Vexi::FeatureFlag.from_hash(original_hash)

      second_hash = first_ff.to_hash

      second_ff = Vexi::FeatureFlag.from_hash(second_hash)

      assert_equal original_hash, second_hash
      assert_equal first_ff, second_ff
    end

    it "ensure no data loss with conversions back and forth from an original hash with boolean_gate true" do
      original_hash = {
        "name" => "test_flag",
        "boolean_gate" => true,
        "percentage_of_actors" => 33.2,
        "percentage_of_calls" => 12.8,
        "custom_gates" => ["gate1", "gate2"],
        "actors" => ["User:1", "Repository:10"],
        "segments" => ["segment1", "segment2"],
      }

      first_ff = Vexi::FeatureFlag.from_hash(original_hash)

      second_hash = first_ff.to_hash

      second_ff = Vexi::FeatureFlag.from_hash(second_hash)

      assert_equal original_hash, second_hash
      assert_equal first_ff, second_ff
    end
  end
end
