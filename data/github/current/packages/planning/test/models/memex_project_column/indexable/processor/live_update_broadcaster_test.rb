# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumn::Indexable::Processor::LiveUpdateBroadcasterTest < GitHub::TestCase
  setup do
    GitHub.flipper[:memex_live_update_gids].disable
  end

  fixtures do
    @user = create(:user)
    @project = create(:memex_project, owner: @user)
  end

  context "#call" do
    test "with enabled flag, broadcasts when passed in ids and timestamp" do
      GitHub.flipper[:memex_table_without_limits].enable

      timestamp = Time.now.to_i
      MemexProject.any_instance.expects(:notify_memex_channel).once.with({ type: "memex_item_denormalized_to_elasticsearch" , timestamp: })
      klass.new(memex_project_ids: [@project.id], timestamp:).call
    end

    test "with enabled flag, broadcasts when passed in ids" do
      GitHub.flipper[:memex_table_without_limits].enable

      MemexProject.any_instance.expects(:notify_memex_channel).once
      klass.new(memex_project_ids: [@project.id], timestamp: Time.now.to_i).call
    end

    test "with enabled flag and enabled gids flag, broadcasts when passed in ids, timestamp, and updated gids" do
      GitHub.flipper[:memex_table_without_limits].enable
      GitHub.flipper[:memex_live_update_gids].enable

      issue = create(:issue, state: "open", user: @user)
      item = create(:memex_project_item, content: issue, memex_project: @project)
      other_item = create(:memex_project_item) # An item from another project, should be excluded
      timestamp = Time.now.to_i

      MemexProject.any_instance.expects(:notify_memex_channel).once.with({
        type: "memex_item_denormalized_to_elasticsearch",
        timestamp:,
        models: [issue.global_relay_id],
        items: [{
          id: item.id,
          gid: item.global_relay_id,
        }]
      })

      klass.new(
        memex_project_ids: [@project.id],
        timestamp:,
        updated_models: [issue, item, other_item],
      ).call
    end

    test "does not broadcast when passed an empty set of ids" do
      GitHub.flipper[:memex_table_without_limits].enable

      MemexProject.any_instance.expects(:notify_memex_channel).never
      klass.new(memex_project_ids: [], timestamp: Time.now.to_i).call
    end

    test "does not broadcast when flag is disabled" do
      GitHub.flipper[:memex_table_without_limits].disable

      MemexProject.any_instance.expects(:notify_memex_channel).never
      klass.new(memex_project_ids: [], timestamp: Time.now.to_i).call
    end
  end

  private def klass
    MemexProjectColumn::Indexable::Processor::LiveUpdateBroadcaster
  end
end
