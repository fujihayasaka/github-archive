# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class MergeQueueSerializersTest < Api::SerializerTestCase
  fixtures do
    @owner       = create(:user)
    @org         = create(:organization, admin: @owner)
    @repo        = create(:repository, owner: @org)
    @merge_queue = create(:merge_queue, repository: @repo)
  end

  context "merge_queue" do
    test "returns nil when given nil" do
      output = merge_queue(nil)
      assert_nil output
    end

    test "serializes correctly" do
      actual = merge_queue(@merge_queue)
      expected = {
        "id" => @merge_queue.id,
        "node_id" => @merge_queue.global_relay_id,
      }
      assert_equal expected, actual
    end
  end

  context "merge_queue_entry" do
    test "returns nil when given nil" do
      output = merge_queue_entry(nil)
      assert_nil output
    end

    test "serializes correctly" do
      entry = create(:merge_queue_entry)
      actual = merge_queue_entry(entry)
      expected = {
        "id" => entry.id,
        "is_solo" => entry.solo?,
        "node_id" => entry.global_relay_id,
      }
      assert_equal expected, actual
    end
  end

  private

  def merge_queue(...)
    # Implemented by `Api::SerializerTestCase#method_missing`
    T.bind(self, T.untyped)
    super
  end

  def merge_queue_entry(...)
    # Implemented by `Api::SerializerTestCase#method_missing`
    T.bind(self, T.untyped)
    super
  end

end
