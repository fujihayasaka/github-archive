# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCampaigns
  class ReopeningServiceTest < GitHub::TestCase
    include HydroTestHelpers

    # These tests are not compatible with enterprise and
    # the reopening service should not be used in enterprise
    skip_enterprise

    fixtures do
      GitHub::Enterprise.ensure_business!

      @manager = create(:user)
      @current_user = create(:user)

      @org = create(:organization)
      @open_campaign = create(:security_campaign, organization: @org)
      @closed_campaign = create(
        :security_campaign,
        organization: @org,
        closed_at: Time.now,
        closure_open_count: 3,
        closure_closed_count: 2,
        closure_dismissed_count: 1,
        closure_autofix_supported_count: 5,
        closure_autofix_generated_count: 4,
        closure_autofix_accepted_count: 3
      )
    end

    context "call" do
      test "reopens a campaign" do
        refute @closed_campaign.open?

        ReopeningService.call(campaign: @closed_campaign, org: @org, actor: @current_user)

        assert @closed_campaign.reload.open?
        assert_nil @closed_campaign.closed_at
        assert_nil @closed_campaign.closure_open_count
        assert_nil @closed_campaign.closure_closed_count
        assert_nil @closed_campaign.closure_dismissed_count
        assert_nil @closed_campaign.closure_autofix_supported_count
        assert_nil @closed_campaign.closure_autofix_generated_count
        assert_nil @closed_campaign.closure_autofix_accepted_count
      end

      test "raises error if the maximum number of open campaigns for the organization has been reached" do
        (SecurityCampaigns::MAX_OPEN_CAMPAIGNS_COUNT - 1).times do # -1 because we create 1 open campaign in the fixtures
          create(:security_campaign, organization: @org)
        end

        assert_raises(ActiveRecord::RecordNotSaved) do
          ReopeningService.call(campaign: @closed_campaign, org: @org, actor: @current_user)
        end

        refute @closed_campaign.reload.open?
      end

      test "publishes hydro event" do
        refute @closed_campaign.open?

        ReopeningService.call(campaign: @closed_campaign, org: @org, actor: @current_user)

        @closed_campaign.reload

        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(@current_user),
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          organization: Hydro::EntitySerializer.organization(@org),
          security_campaign: {
            id: @closed_campaign.id,
            number: @closed_campaign.number,
            name: @closed_campaign.name,
            organization_id: @closed_campaign.organization_id,
            due_date: @closed_campaign.ends_at,
            created_at: @closed_campaign.created_at,
            updated_at: @closed_campaign.updated_at,
            closed_at: @closed_campaign.closed_at,
          },
          user_managers: @closed_campaign.user_manager_users.map { |user| Hydro::EntitySerializer.user(user) },
          team_managers: [],
        }, schema: "github.security_campaigns.v0.SecurityCampaignReopen")
      end
    end
  end
end
