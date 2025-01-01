# typed: false
# frozen_string_literal: true

require "test_helper"

module TasklistBlocks
  class CompletionTest < GitHub::TestCase
    include IssuesGraphTestHelpers

    context "from_proto" do
      test "initializes model from protobuf" do
        proto_completion = build_proto_completion(
          key: build_proto_key(
            owner_id: 1,
            item_id: 2,
            uuid: "1-1-1-1"
          ),
          completed: 5,
          total: 15,
          percent: 33
        )
        completion = TasklistBlocks::Completion.from_proto(completion: proto_completion)
        assert_equal 5, completion.completed
        assert_equal 15, completion.total
        assert_equal 33, completion.percent
      end

      test "is nilable" do
        completion = TasklistBlocks::Completion.from_proto(completion: nil)
        assert_nil completion
      end
    end

    test "to_h returns serialized completion" do
      completion = TasklistBlocks::Completion.new(
        uuid: "1-1-1-1",
        completed: 5,
        total: 15,
        percent: 33
      )
      expected_hash = {
        uuid: "1-1-1-1",
        completed: 5,
        total: 15,
        percent: 33
      }
      assert_equal expected_hash, completion.to_h
    end
  end
end
