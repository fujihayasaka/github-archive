# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumn::Interface::Indexable::Processor::LiveUpdateBroadcasterTest < GitHub::TestCase
  setup do
    GitHub.flipper[:memex_live_update_gids].disable
    GitHub.flipper[:memex_table_without_limits].disable
    GitHub.flipper[:memex_project_without_limits_public_beta].disable
    GitHub.flipper[:memex_table_without_limits_disabled].disable
  end

  fixtures do
    @user = create(:user)
    @project = create(:memex_project, owner: @user)
    @org_project = create(:memex_project, owner: create(:organization))
  end

  context "#call" do
    test "with limited beta flag enabled, broadcasts when passed in ids and timestamp" do
      GitHub.flipper[:memex_table_without_limits].enable

      timestamp = Time.now.to_i
      MemexProject.any_instance.expects(:notify_memex_channel).once.with({ type: "memex_item_denormalized_to_elasticsearch", timestamp: })
      klass.new(memex_project_ids: [@project.id], timestamp:).call
    end

    test "with public beta flag enabled, broadcasts when passed in ids and timestamp" do
      GitHub.flipper[:memex_project_without_limits_public_beta].enable(@org_project.owner)

      timestamp = Time.now.to_i
      MemexProject.any_instance.expects(:notify_memex_channel).once.with({ type: "memex_item_denormalized_to_elasticsearch", timestamp: })
      klass.new(memex_project_ids: [@org_project.id], timestamp:).call
    end

    test "with limited beta flag enabled, broadcasts when passed in ids" do
      GitHub.flipper[:memex_table_without_limits].enable

      MemexProject.any_instance.expects(:notify_memex_channel).once
      klass.new(memex_project_ids: [@project.id], timestamp: Time.now.to_i).call
    end

    test "with public beta flag enabled, broadcasts when passed in ids" do
      GitHub.flipper[:memex_project_without_limits_public_beta].enable(@org_project.owner)

      MemexProject.any_instance.expects(:notify_memex_channel).once
      klass.new(memex_project_ids: [@org_project.id], timestamp: Time.now.to_i).call
    end

    test "with limited beta flag enabled and enabled gids flag, broadcasts when passed in ids, timestamp, and updated gids" do
      GitHub.flipper[:memex_table_without_limits].enable
      GitHub.flipper[:memex_live_update_gids].enable

      issue = create(:issue, state: "open", user: @user)
      item = create(:memex_project_item, content: issue, memex_project: @project)
      other_item = create(:memex_project_item) # An item from another project, should be excluded
      timestamp = Time.now.to_i

      MemexProject.any_instance.expects(:notify_memex_channel).once.with({
        type: "memex_item_denormalized_to_elasticsearch",
        timestamp:,
        source_type: "SomeTopic",
        models: [issue.global_relay_id],
        items: [{
          id: item.id,
          gid: item.global_relay_id,
        }],
      })

      klass.new(
        memex_project_ids: [@project.id],
        timestamp:,
        source_topic: "cp1-iad.ingest.SomeTopic",
        updated_models: [issue, item, other_item]
      ).call
    end

    test "with public beta flag enabled and enabled gids flag, broadcasts when passed in ids, timestamp, and updated gids" do
      GitHub.flipper[:memex_project_without_limits_public_beta].enable(@org_project.owner)
      GitHub.flipper[:memex_live_update_gids].enable

      issue = create(:issue, state: "open", user: @user)
      item = create(:memex_project_item, content: issue, memex_project: @org_project)
      other_item = create(:memex_project_item) # An item from another project, should be excluded
      timestamp = Time.now.to_i

      MemexProject.any_instance.expects(:notify_memex_channel).once.with({
        type: "memex_item_denormalized_to_elasticsearch",
        timestamp:,
        source_type: "SomeTopic",
        models: [issue.global_relay_id],
        items: [{
          id: item.id,
          gid: item.global_relay_id,
        }],
      })

      klass.new(
        memex_project_ids: [@org_project.id],
        timestamp:,
        source_topic: "cp1-iad.ingest.SomeTopic",
        updated_models: [issue, item, other_item]
      ).call
    end

    [:memex_table_without_limits, :memex_project_without_limits_public_beta].each do |feature_flag|
      test "does not broadcast when passed an empty set of ids with #{feature_flag} enabled" do
        GitHub.flipper[feature_flag].enable

        MemexProject.any_instance.expects(:notify_memex_channel).never
        klass.new(memex_project_ids: [], timestamp: Time.now.to_i).call
      end

      test "does not broadcast when #{feature_flag} flag is disabled" do
        GitHub.flipper[feature_flag].disable

        MemexProject.any_instance.expects(:notify_memex_channel).never
        klass.new(memex_project_ids: [], timestamp: Time.now.to_i).call
      end
    end

    test "with public beta flag enabled and table without limits disabled, does not broadcasts for denormalization" do
      GitHub.flipper[:memex_project_without_limits_public_beta].enable(@org_project.owner)
      GitHub.flipper[:memex_table_without_limits_disabled].enable(@org_project)

      timestamp = Time.now.to_i
      MemexProject.any_instance.expects(:notify_memex_channel).never.with({ type: "memex_item_denormalized_to_elasticsearch", timestamp: })
      klass.new(memex_project_ids: [@org_project.id], timestamp:).call
    end
  end

  private def klass
    MemexProjectColumn::Interface::Indexable::Processor::LiveUpdateBroadcaster
  end
end
