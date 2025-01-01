# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class SecurityCampaignUserAdapterTest < GitHub::TestCase
    fixtures do
      @actor = create(:user)
      @campaign_user = create(:security_campaign_user)
    end

    context "#alert_counts_by_repo" do
      test "parses repo_counts_by_repo" do
        context = {
          actor_id: @actor.id,
          actor_login: @actor.display_login,
          operation: Notifyd::Operations::SecurityCampaignUserOperation::Overdue.serialize,
          repo_counts_by_repo: { 1 => 2, 3 => 4 }.to_json,
        }
        adapter = SecurityCampaignUserAdapter.new(@campaign_user, context)

        assert_equal({ 1 => 2, 3 => 4 }, adapter.alert_counts_by_repo)
      end

      test "parses alert_counts_by_repo" do
        context = {
          actor_id: @actor.id,
          actor_login: @actor.display_login,
          operation: Notifyd::Operations::SecurityCampaignUserOperation::Overdue.serialize,
          alert_counts_by_repo: { "5" => 6, "7" => 8 },
        }
        adapter = SecurityCampaignUserAdapter.new(@campaign_user, context)

        assert_equal({ 5 => 6, 7 => 8 }, adapter.alert_counts_by_repo)
      end

      test "handles when both repo_counts_by_repo and alert_counts_by_repo missing" do
        context = {
          actor_id: @actor.id,
          actor_login: @actor.display_login,
          operation: Notifyd::Operations::SecurityCampaignUserOperation::Create.serialize,
        }
        adapter = SecurityCampaignUserAdapter.new(@campaign_user, context)

        assert_equal({}, adapter.alert_counts_by_repo)
      end
    end
  end
end
