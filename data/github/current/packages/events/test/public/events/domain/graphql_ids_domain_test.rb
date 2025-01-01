# typed: true
# frozen_string_literal: true

require "test_helper"

class GraphQLIDsDomainTest < GitHub::TestCase
  class TestModelWithGraphQLIds
    attr_reader :global_relay_id, :next_global_id
    attr_accessor :platform_type_name

    def initialize(global_relay_id:, next_global_id:)
      @global_relay_id = global_relay_id
      @next_global_id = next_global_id
    end
  end

  class TestModelWithNoGraphQLIds
    def global_relay_id
      raise ArgumentError, "oops"
    end

    def next_global_id
      raise ArgumentError, "oops"
    end
  end

  setup do
    @domain = Events::Domain.new
  end

  context "graphql_ids" do
    test "graphql id's are returned if available" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      test_model = TestModelWithGraphQLIds.new(global_relay_id: "123", next_global_id: "456")
      Platform::Helpers::NodeIdentification.expects(:type_from_object).with(test_model).returns("value")
      result = @domain.graphql_ids(test_model)
      assert_equal "123", result.global_relay_id
      assert_equal "456", result.next_global_id
      assert_equal 0, GitHub.dogstats.increments("hooks.domain.graphql_ids.error").count
    end

    test "graphql id's are not returned if not available" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      test_model = TestModelWithNoGraphQLIds.new
      result = @domain.graphql_ids(test_model)
      assert_nil result.global_relay_id
      assert_nil result.next_global_id
      assert_equal 0, GitHub.dogstats.increments("hooks.domain.graphql_ids.error").count
    end

    test "metrics are incremented if we still get ArgumentError's when calling next_global_id or global_relay_id" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      test_model = TestModelWithGraphQLIds.new(global_relay_id: "123", next_global_id: "456")
      Platform::Helpers::NodeIdentification.expects(:type_from_object).with(test_model).returns("value")
      test_model.expects(:global_relay_id).raises(ArgumentError, "oops")
      test_model.expects(:next_global_id).raises(ArgumentError, "oops")
      result = @domain.graphql_ids(test_model)
      assert_nil result.global_relay_id
      assert_nil result.next_global_id
      assert_equal 1, GitHub.dogstats.increments("hooks.domain.graphql_ids.error", tags: ["call:next_global_id", "error:argument_error"]).count
      assert_equal 1, GitHub.dogstats.increments("hooks.domain.graphql_ids.error", tags: ["call:global_relay_id", "error:argument_error"]).count
    end

    test "metrics are incremented if we get an unexpected error" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      test_model = TestModelWithNoGraphQLIds.new
      test_model.expects(:respond_to?).with(:platform_type_name).returns(true).once
      Platform::Helpers::NodeIdentification.expects(:type_from_object).raises(StandardError, "oops")
      @domain.graphql_ids(test_model)
      assert_equal 1, GitHub.dogstats.increments("hooks.domain.graphql_ids.error", tags: ["call:graphql_ids", "error:unknown"]).count
    end
  end
end
