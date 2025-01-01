# typed: true
# frozen_string_literal: true

require "test_helper"

class TasklistBlocks::PrimaryKeyTest < GitHub::TestCase
  include IssuesGraphTestHelpers

  context "from_proto" do
    test "initializes model from protobuf" do
      proto_key = build_proto_primary_key(
        uuid: "7b321716-e2fa-54b6-8b49-07b03607b717"
      )
      result = klass.from_proto(key: proto_key)
      assert_equal "7b321716-e2fa-54b6-8b49-07b03607b717", result.uuid
    end
  end

  private

  def klass
    TasklistBlocks::PrimaryKey
  end
end
