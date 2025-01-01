# typed: true
# frozen_string_literal: true

require "test_helper"

class TasklistBlockCommands::ExtractPositionFromUrlTasklistTest < GitHub::TestCase
  include IssuesGraphTestHelpers

  fixtures do
    @issue = create(:issue)
  end

  context ":add" do
    test "happy path returns an integer representing the block position" do
      block_uuid = SecureRandom.uuid
      block_key = build_proto_key(uuid: block_uuid)
      hierarchy_result = build_get_issue_success_response(
        issue: to_proto_issue(@issue),
        tracking: [build_proto_tasklist_block(key: block_key)],
      )
      stub_issue_hierarchy(issue: @issue, result: hierarchy_result)

      result = klass.new(
        action: :add,
        issue: @issue,
        block_uuid: block_uuid
      ).call

      assert_predicate result, :success?
      assert_equal 0, result.data
    end

    test "works for non zero positions too" do
      block_uuid = SecureRandom.uuid
      block_key = build_proto_key(uuid: block_uuid)
      hierarchy_result = build_get_issue_success_response(
        issue: to_proto_issue(@issue),
        tracking: [
          build_proto_tasklist_block,
          build_proto_tasklist_block(key: block_key),
        ]
      )
      stub_issue_hierarchy(issue: @issue, result: hierarchy_result)

      result = klass.new(
        action: :add,
        issue: @issue,
        block_uuid: block_uuid
      ).call

      assert_predicate result, :success?
      assert_equal 1, result.data
    end

    test "block not found returns a fail result" do
      block_uuid = SecureRandom.uuid
      other_block_uuid = SecureRandom.uuid
      block_key = build_proto_key(uuid: block_uuid)
      hierarchy_result = build_get_issue_success_response(
        issue: to_proto_issue(@issue),
        tracking: [build_proto_tasklist_block(key: block_key)],
      )
      stub_issue_hierarchy(issue: @issue, result: hierarchy_result)

      result = klass.new(
        action: :add,
        issue: @issue,
        block_uuid: other_block_uuid
      ).call

      refute_predicate result, :success?
    end
  end

  context ":remove" do
    test "happy path returns an array of integer representing" \
      "the block position and item position" do
      block_uuid = SecureRandom.uuid
      item_uuid = SecureRandom.uuid
      block_key = build_proto_key(uuid: block_uuid)
      hierarchy_result = build_get_issue_success_response(
        issue: to_proto_issue(@issue),
        tracking: [build_proto_tasklist_block(
          key: block_key,
          issues: [build_proto_issue(key: build_proto_key(uuid: item_uuid))],
        )],
      )
      stub_issue_hierarchy(issue: @issue, result: hierarchy_result)

      result = klass.new(
        action: :remove,
        issue: @issue,
        block_uuid: block_uuid,
        item_uuid: item_uuid
      ).call

      assert_predicate result, :success?
      assert_equal [0, 0], result.data
    end

    test "happy path returns an array of integer representing" \
      "the block position and item position even when not at position 0,0" do
      block_uuid = SecureRandom.uuid
      item_uuid = SecureRandom.uuid
      block_key = build_proto_key(uuid: block_uuid)
      hierarchy_result = build_get_issue_success_response(
        issue: to_proto_issue(@issue),
        tracking: [build_proto_tasklist_block(
          key: block_key,
          issues: [
            build_proto_issue,
            build_proto_issue(key: build_proto_key(uuid: item_uuid))
          ],
        )],
      )
      stub_issue_hierarchy(issue: @issue, result: hierarchy_result)

      result = klass.new(
        action: :remove,
        issue: @issue,
        block_uuid: block_uuid,
        item_uuid: item_uuid
      ).call

      assert_predicate result, :success?
      assert_equal [0, 1], result.data
    end

    test "block not found returns a fail result" do
      other_block_uuid = SecureRandom.uuid
      block_uuid = SecureRandom.uuid
      item_uuid = SecureRandom.uuid
      block_key = build_proto_key(uuid: block_uuid)
      hierarchy_result = build_get_issue_success_response(
        issue: to_proto_issue(@issue),
        tracking: [build_proto_tasklist_block(
          key: block_key,
          issues: [
            build_proto_issue,
            build_proto_issue(key: build_proto_key(uuid: item_uuid))
          ],
        )],
      )
      stub_issue_hierarchy(issue: @issue, result: hierarchy_result)

      result = klass.new(
        action: :remove,
        issue: @issue,
        block_uuid: other_block_uuid, # not found :sob:
        item_uuid: item_uuid
      ).call

      refute_predicate result, :success?
    end

    test "item not found returns a fail result" do
      other_item_uuid = SecureRandom.uuid
      block_uuid = SecureRandom.uuid
      item_uuid = SecureRandom.uuid
      block_key = build_proto_key(uuid: block_uuid)
      hierarchy_result = build_get_issue_success_response(
        issue: to_proto_issue(@issue),
        tracking: [build_proto_tasklist_block(
          key: block_key,
          issues: [
            build_proto_issue,
            build_proto_issue(key: build_proto_key(uuid: item_uuid))
          ],
        )],
      )
      stub_issue_hierarchy(issue: @issue, result: hierarchy_result)

      result = klass.new(
        action: :remove,
        issue: @issue,
        block_uuid: block_uuid,
        item_uuid: other_item_uuid # not found :sob:
      ).call

      refute_predicate result, :success?
    end
  end

  context ":convert_to_issue" do
    test "happy path returns an array of integer representing" \
      "the block position and item position" do
      block_uuid = SecureRandom.uuid
      item_uuid = SecureRandom.uuid
      block_key = build_proto_key(uuid: block_uuid)
      hierarchy_result = build_get_issue_success_response(
        issue: to_proto_issue(@issue),
        tracking: [build_proto_tasklist_block(
          key: block_key,
          issues: [build_proto_issue(key: build_proto_key(uuid: item_uuid))],
        )],
      )
      stub_issue_hierarchy(issue: @issue, result: hierarchy_result)

      result = klass.new(
        action: :convert_to_issue,
        issue: @issue,
        block_uuid: block_uuid,
        item_uuid: item_uuid
      ).call

      assert_predicate result, :success?
      assert_equal [0, 0], result.data
    end

    test "happy path returns an array of integer representing" \
      "the block position and item position even when not at position 0,0" do
      block_uuid = SecureRandom.uuid
      item_uuid = SecureRandom.uuid
      block_key = build_proto_key(uuid: block_uuid)
      hierarchy_result = build_get_issue_success_response(
        issue: to_proto_issue(@issue),
        tracking: [build_proto_tasklist_block(
          key: block_key,
          issues: [
            build_proto_issue,
            build_proto_issue(key: build_proto_key(uuid: item_uuid))
          ],
        )],
      )
      stub_issue_hierarchy(issue: @issue, result: hierarchy_result)

      result = klass.new(
        action: :convert_to_issue,
        issue: @issue,
        block_uuid: block_uuid,
        item_uuid: item_uuid
      ).call

      assert_predicate result, :success?
      assert_equal [0, 1], result.data
    end

    test "block not found returns a fail result" do
      other_block_uuid = SecureRandom.uuid
      block_uuid = SecureRandom.uuid
      item_uuid = SecureRandom.uuid
      block_key = build_proto_key(uuid: block_uuid)
      hierarchy_result = build_get_issue_success_response(
        issue: to_proto_issue(@issue),
        tracking: [build_proto_tasklist_block(
          key: block_key,
          issues: [
            build_proto_issue,
            build_proto_issue(key: build_proto_key(uuid: item_uuid))
          ],
        )],
      )
      stub_issue_hierarchy(issue: @issue, result: hierarchy_result)

      result = klass.new(
        action: :convert_to_issue,
        issue: @issue,
        block_uuid: other_block_uuid, # not found :sob:
        item_uuid: item_uuid
      ).call

      refute_predicate result, :success?
    end

    test "item not found returns a fail result" do
      other_item_uuid = SecureRandom.uuid
      block_uuid = SecureRandom.uuid
      item_uuid = SecureRandom.uuid
      block_key = build_proto_key(uuid: block_uuid)
      hierarchy_result = build_get_issue_success_response(
        issue: to_proto_issue(@issue),
        tracking: [build_proto_tasklist_block(
          key: block_key,
          issues: [
            build_proto_issue,
            build_proto_issue(key: build_proto_key(uuid: item_uuid))
          ],
        )],
      )
      stub_issue_hierarchy(issue: @issue, result: hierarchy_result)

      result = klass.new(
        action: :convert_to_issue,
        issue: @issue,
        block_uuid: block_uuid,
        item_uuid: other_item_uuid # not found :sob:
      ).call

      refute_predicate result, :success?
    end
  end

  context ":update_issue_position" do
    test "destination position is correctly calculated when repositioning the item before its current position" do
      # arrange
      block_uuid = SecureRandom.uuid
      target_item_uuid = SecureRandom.uuid
      item_a1_uuid = SecureRandom.uuid
      item_a2_uuid = SecureRandom.uuid
      item_a4_uuid = SecureRandom.uuid

      target_item = build_proto_issue(
        key: build_proto_key(uuid: target_item_uuid),
        title: SecureRandom.hex,
      )
      item_a1 = build_proto_issue(
        key: build_proto_key(uuid: item_a1_uuid),
        title: SecureRandom.hex,
      )
      item_a2 = build_proto_issue(
        key: build_proto_key(uuid: item_a2_uuid),
        title: SecureRandom.hex,
      )
      item_a4 = build_proto_issue(
        key: build_proto_key(uuid: item_a4_uuid),
        title: SecureRandom.hex
      )

      tasklist_items = [
        item_a1,
        item_a2,
        target_item,
        item_a4
      ]

      source_position = 2

      hierarchy_result = build_get_issue_success_response(
        issue: to_proto_issue(@issue),
        tracking: [
          build_proto_tasklist_block(
            key: build_proto_key(uuid: block_uuid),
            issues: tasklist_items,
          )
        ]
      )
      stub_issue_hierarchy(issue: @issue, result: hierarchy_result)

      # act
      result = klass.new(
        action: :update_issue_position,
        issue: @issue,
        block_uuid: block_uuid,
        item_uuid: target_item_uuid,
        previous_item_uuid: item_a1_uuid,
        next_item_uuid: item_a2_uuid,
      ).call

      # assert
      source, destination = result.data
      assert_equal [0, source_position], source
      assert_equal [0, 1], destination
    end

    test "destination position is correctly calculated when repositioning the item after its current position" do
      # arrange
      block_uuid = SecureRandom.uuid
      target_item_uuid = SecureRandom.uuid
      item_a1_uuid = SecureRandom.uuid
      item_a3_uuid = SecureRandom.uuid
      item_a4_uuid = SecureRandom.uuid

      target_item = build_proto_issue(
        key: build_proto_key(uuid: target_item_uuid),
        title: SecureRandom.hex,
      )
      item_a1 = build_proto_issue(
        key: build_proto_key(uuid: item_a1_uuid),
        title: SecureRandom.hex,
      )
      item_a3 = build_proto_issue(
        key: build_proto_key(uuid: item_a3_uuid),
        title: SecureRandom.hex,
      )
      item_a4 = build_proto_issue(
        key: build_proto_key(uuid: item_a4_uuid),
        title: SecureRandom.hex
      )

      tasklist_items = [
        item_a1,
        target_item,
        item_a3,
        item_a4
      ]

      source_position = 1

      hierarchy_result = build_get_issue_success_response(
        issue: to_proto_issue(@issue),
        tracking: [
          build_proto_tasklist_block(
            key: build_proto_key(uuid: block_uuid),
            issues: tasklist_items,
          )
        ]
      )
      stub_issue_hierarchy(issue: @issue, result: hierarchy_result)

      # act
      result = klass.new(
        action: :update_issue_position,
        issue: @issue,
        block_uuid: block_uuid,
        item_uuid: target_item_uuid,
        previous_item_uuid: item_a3_uuid,
        next_item_uuid: item_a4_uuid,
      ).call

      # assert
      source, destination = result.data
      assert_equal [0, source_position], source
      assert_equal [0, 2], destination
    end

    test "destination position is correctly calculated when repositioning the item before every item" do
      # arrange
      block_uuid = SecureRandom.uuid
      target_item_uuid = SecureRandom.uuid
      item_a1_uuid = SecureRandom.uuid
      item_a3_uuid = SecureRandom.uuid
      item_a4_uuid = SecureRandom.uuid

      target_item = build_proto_issue(
        key: build_proto_key(uuid: target_item_uuid),
        title: SecureRandom.hex,
      )
      item_a1 = build_proto_issue(
        key: build_proto_key(uuid: item_a1_uuid),
        title: SecureRandom.hex,
      )
      item_a3 = build_proto_issue(
        key: build_proto_key(uuid: item_a3_uuid),
        title: SecureRandom.hex,
      )
      item_a4 = build_proto_issue(
        key: build_proto_key(uuid: item_a4_uuid),
        title: SecureRandom.hex
      )

      tasklist_items = [
        item_a1,
        target_item,
        item_a3,
        item_a4
      ]

      source_position = 1

      hierarchy_result = build_get_issue_success_response(
        issue: to_proto_issue(@issue),
        tracking: [
          build_proto_tasklist_block(
            key: build_proto_key(uuid: block_uuid),
            issues: tasklist_items,
          )
        ]
      )
      stub_issue_hierarchy(issue: @issue, result: hierarchy_result)

      # act
      result = klass.new(
        action: :update_issue_position,
        issue: @issue,
        block_uuid: block_uuid,
        item_uuid: target_item_uuid,
        previous_item_uuid: "null",
        next_item_uuid: item_a1_uuid,
      ).call

      # assert
      source, destination = result.data
      assert_equal [0, source_position], source
      assert_equal [0, 0], destination
    end

    test "destination position is correctly calculated when repositioning the item after every item" do
      # arrange
      block_uuid = SecureRandom.uuid
      target_item_uuid = SecureRandom.uuid
      item_a1_uuid = SecureRandom.uuid
      item_a3_uuid = SecureRandom.uuid
      item_a4_uuid = SecureRandom.uuid

      target_item = build_proto_issue(
        key: build_proto_key(uuid: target_item_uuid),
        title: SecureRandom.hex,
      )
      item_a1 = build_proto_issue(
        key: build_proto_key(uuid: item_a1_uuid),
        title: SecureRandom.hex,
      )
      item_a3 = build_proto_issue(
        key: build_proto_key(uuid: item_a3_uuid),
        title: SecureRandom.hex,
      )
      item_a4 = build_proto_issue(
        key: build_proto_key(uuid: item_a4_uuid),
        title: SecureRandom.hex
      )

      tasklist_items = [
        item_a1,
        target_item,
        item_a3,
        item_a4
      ]

      source_position = 1

      hierarchy_result = build_get_issue_success_response(
        issue: to_proto_issue(@issue),
        tracking: [
          build_proto_tasklist_block(
            key: build_proto_key(uuid: block_uuid),
            issues: tasklist_items,
          )
        ]
      )
      stub_issue_hierarchy(issue: @issue, result: hierarchy_result)

      # act
      result = klass.new(
        action: :update_issue_position,
        issue: @issue,
        block_uuid: block_uuid,
        item_uuid: target_item_uuid,
        previous_item_uuid: item_a4_uuid,
        next_item_uuid: "null",
      ).call

      # assert
      source, destination = result.data
      assert_equal [0, source_position], source
      assert_equal [0, 3], destination
    end

    test "repositioning across tasklists returns a fail result" do
      # arrange
      block_uuid = SecureRandom.uuid
      other_block_uuid = SecureRandom.uuid
      target_item_uuid = SecureRandom.uuid
      item_a1_uuid = SecureRandom.uuid

      target_item = build_proto_issue(
        key: build_proto_key(uuid: target_item_uuid),
        title: SecureRandom.hex,
      )
      item_a1 = build_proto_issue(
        key: build_proto_key(uuid: item_a1_uuid),
        title: SecureRandom.hex,
      )

      hierarchy_result = build_get_issue_success_response(
        issue: to_proto_issue(@issue),
        tracking: [
          build_proto_tasklist_block(
            key: build_proto_key(uuid: block_uuid),
            issues: [
              item_a1,
              target_item,
            ],
          )
        ]
      )
      stub_issue_hierarchy(issue: @issue, result: hierarchy_result)

      # act
      result = klass.new(
        action: :update_issue_position,
        issue: @issue,
        block_uuid: other_block_uuid,
        item_uuid: target_item_uuid,
        previous_item_uuid: "null",
        next_item_uuid: item_a1_uuid,
      ).call

      # assert
      refute_predicate result, :success?
    end
  end

  private

  def klass
    TasklistBlockCommands::ExtractPositionFromUrlTasklist
  end
end
