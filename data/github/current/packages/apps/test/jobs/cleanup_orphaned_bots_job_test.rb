# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CleanupOrphanedBotsJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper

  fixtures do
    3.times { create(:integration) }
    integration = Integration.last
    @bot = integration.bot
    # destroy without callbacks to simulate orphaned bots
    integration.delete
    assert_predicate Bot.where(id: @bot.id), :exists?
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  test "does not cleanup if the flippers are disabled and it is not on enterprise", skip_enterprise: true do
    GitHub.flipper[:cleanup_orphaned_bots].disable
    GitHub.flipper[:cleanup_orphaned_bots_destroy].disable

    assert_no_difference "Bot.count" do
      CleanupOrphanedBotsJob.perform_now
    end
  end

  test "cleans up orphaned bots if the flippers are disabled but it is on enterprise", enterprise_only: true do
    GitHub.flipper[:cleanup_orphaned_bots].disable
    GitHub.flipper[:cleanup_orphaned_bots_destroy].disable

    expected_log = {
      "gh.job.name" => "CleanupOrphanedBotsJob",
      "identified_orphaned_bot_ids" => [@bot.id],
      "removed_orphaned_bot_ids" => [@bot.id],
    }

    assert_difference "Bot.count", -1 do
      CleanupOrphanedBotsJob.stub_const(:BATCH_SIZE, 1) do
        assert_logged(**expected_log) do
          CleanupOrphanedBotsJob.perform_now

          metric = "cleanup_orphaned_bots_job.orphaned_bots"
          expected_tags = ["all_removed:true"]
          assert_equal 1, GitHub.dogstats.distributions(metric, tags: expected_tags).length
        end
      end
    end
  end

  test "does not cleanup if the destroy flipper is disabled and it is not on enterprise", skip_enterprise: true do
    GitHub.flipper[:cleanup_orphaned_bots].enable
    GitHub.flipper[:cleanup_orphaned_bots_destroy].disable

    expected_log = {
      "gh.job.name" => "CleanupOrphanedBotsJob",
      "identified_orphaned_bot_ids" => [@bot.id],
      "removed_orphaned_bot_ids" => [],
    }

    assert_no_difference "Bot.count" do
      CleanupOrphanedBotsJob.stub_const(:BATCH_SIZE, 1) do
        assert_logged(**expected_log) do
          CleanupOrphanedBotsJob.perform_now

          metric = "cleanup_orphaned_bots_job.orphaned_bots"
          expected_tags = ["all_removed:false"]
          assert_equal 1, GitHub.dogstats.distributions(metric, tags: expected_tags).length
        end
      end
    end
  end

  test "clean up if the destroy flipper is disabled and it is on enterprise", enterprise_only: true do
    GitHub.flipper[:cleanup_orphaned_bots].enable
    GitHub.flipper[:cleanup_orphaned_bots_destroy].disable

    expected_log = {
      "gh.job.name" => "CleanupOrphanedBotsJob",
      "identified_orphaned_bot_ids" => [@bot.id],
      "removed_orphaned_bot_ids" => [@bot.id],
    }

    assert_difference "Bot.count", -1 do
      CleanupOrphanedBotsJob.stub_const(:BATCH_SIZE, 1) do
        assert_logged(**expected_log) do
          CleanupOrphanedBotsJob.perform_now

          metric = "cleanup_orphaned_bots_job.orphaned_bots"
          expected_tags = ["all_removed:true"]
          assert_equal 1, GitHub.dogstats.distributions(metric, tags: expected_tags).length
        end
      end
    end
  end

  test "cleans up orphaned bots" do
    GitHub.flipper[:cleanup_orphaned_bots].enable
    GitHub.flipper[:cleanup_orphaned_bots_destroy].enable

    expected_log = {
      "gh.job.name" => "CleanupOrphanedBotsJob",
      "identified_orphaned_bot_ids" => [@bot.id],
      "removed_orphaned_bot_ids" => [@bot.id],
    }

    assert_difference "Bot.count", -1 do
      CleanupOrphanedBotsJob.stub_const(:BATCH_SIZE, 1) do
        assert_logged(**expected_log) do
          CleanupOrphanedBotsJob.perform_now

          metric = "cleanup_orphaned_bots_job.orphaned_bots"
          expected_tags = ["all_removed:true"]
          assert_equal 1, GitHub.dogstats.distributions(metric, tags: expected_tags).length
        end
      end
    end
  end
end
