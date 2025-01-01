# typed: true
# frozen_string_literal: true

require "test_helper"

module Analytics
  class VisitorTest < GitHub::TestCase
    context ".with_octolytics_id" do
      test "returns a visitor with the designated octolytics ID" do
        visitor = Visitor.with_octolytics_id("GH1.1.1784622427.1449520462")
        assert_equal "GH1.1.1784622427.1449520462", visitor.octolytics_id
      end

      test "handles missing octolytics IDs" do
        assert_nil Visitor.with_octolytics_id("")
      end

      test "counts malformed octolytics IDs" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        assert_nil Visitor.with_octolytics_id("GH1.1.CANDLES")

        assert_equal 1, GitHub.dogstats.increments("octolytics_id.coercion_error").length
      end
    end

    context ".create" do
      test "creates a new visitor" do
        visitor = Visitor.create

        assert_instance_of Visitor, visitor
        refute_nil visitor.id
      end
    end

    context "#spammy?" do
      test "it returns false" do
        visitor = Visitor.create

        refute visitor.spammy?
      end
    end
  end
end
