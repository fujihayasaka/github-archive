# typed: true
# frozen_string_literal: true

require "test_helper"

class TasklistBlocks::KeyTest < GitHub::TestCase
  include IssuesGraphTestHelpers

  context "from_proto" do
    test "initializes model from protobuf" do
      proto_key = build_proto_key(
        owner_id: 11111111,
        item_id: 2222222222,
        uuid: "7b321716-e2fa-54b6-8b49-07b03607b717"
      )
      result = klass.from_proto(key: proto_key)
      assert_equal 11111111, result.owner_id
      assert_equal 2222222222, result.item_id
      assert_equal "7b321716-e2fa-54b6-8b49-07b03607b717", result.primary_key.uuid
    end
  end

  private

  def klass
    TasklistBlocks::Key
  end
end
