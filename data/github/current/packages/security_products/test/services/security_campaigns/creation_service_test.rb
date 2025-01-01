# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCampaigns
  class CreationServiceTest < GitHub::TestCase
    include HydroTestHelpers

    fixtures do
      GitHub::Enterprise.ensure_business!

      @manager = create(:user)
      @current_user = create(:user)

      @org = create(:organization, admin: @manager)

      @repo1 = create(:private_repository, owner: @org, from_example: :simple)
      @repo2 = create(:private_repository, owner: @org, from_example: :simple)

      @query_string = "is:open"
    end

    setup do
      @logical_alert_info = { @repo1.id => [1, 2], @repo2.id => [3] }
      @campaign = build(:security_campaign, organization: @org, manager: @manager)
    end

    test "creates campaign, alert, and repository records" do
      assert_changes -> { SecurityCampaigns::SecurityCampaign.count }, from: 0, to: 1 do
        assert_changes -> { SecurityCampaigns::SecurityCampaignRepository.count }, from: 0, to: 2 do
          assert_changes -> { SecurityCampaigns::SecurityCampaignAlert.count }, from: 0, to: 3 do
            CreationService.call(campaign: @campaign, logical_alert_info: @logical_alert_info, actor: @current_user, query_string: @query_string)
          end
        end
      end
    end

    test "publishes a hydro event" do
      @logical_alert_info = { @repo1.id => [1, 2], @repo2.id => [2, 3] }
      campaign = CreationService.call(campaign: @campaign, logical_alert_info: @logical_alert_info, actor: @current_user, query_string: @query_string)

      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(@current_user),
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        query: @query_string,
        repo_count: 2,
        alert_count: 4,
        organization: Hydro::EntitySerializer.organization(@org),
        manager: Hydro::EntitySerializer.user(@manager),
        description: @campaign.description,
        security_campaign: {
          id: campaign.id,
          number: campaign.number,
          name: campaign.name,
          organization_id: campaign.organization_id,
          manager_id: campaign.manager_id,
          due_date: campaign.ends_at,
          created_at: campaign.created_at,
          updated_at: campaign.updated_at,
        }
      }, schema: "github.security_campaigns.v0.SecurityCampaignCreate")
    end

    test "skips duplicate records gracefully" do
      @logical_alert_info[@repo1.id] += [1]
      @logical_alert_info[@repo1.id] += [4]

      assert_changes -> { SecurityCampaigns::SecurityCampaign.count }, from: 0, to: 1 do
        assert_changes -> { SecurityCampaigns::SecurityCampaignRepository.count }, from: 0, to: 2 do
          assert_changes -> { SecurityCampaigns::SecurityCampaignAlert.count }, from: 0, to: 4 do
            CreationService.call(campaign: @campaign, logical_alert_info: @logical_alert_info, actor: @current_user, query_string: @query_string)
          end
        end
      end
    end

    test "raises an error if the organization has too many campaigns" do
      exception = assert_raises(ActiveRecord::RecordNotSaved) do
        (SecurityCampaigns::MAX_CAMPAIGNS_COUNT + 1).times do
          campaign = build(:security_campaign, organization: @org, manager: @manager)
          CreationService.call(campaign:, logical_alert_info: @logical_alert_info, actor: @current_user, query_string: @query_string)
        end
      end
      assert_equal MAX_CAMPAIGNS_ERROR_MESSAGE, exception.message
    end

    test "raises an error if the open campaigns limit is reached" do
      (SecurityCampaigns::MAX_CAMPAIGNS_COUNT).times do
        create(:security_campaign, organization: @org)
      end

      create(:security_campaign, organization: @org, closed_at: Time.now)

      exception = assert_raises(ActiveRecord::RecordNotSaved) do
        CreationService.call(campaign: @campaign, logical_alert_info: @logical_alert_info, actor: @current_user, query_string: @query_string)
      end
      assert_equal MAX_CAMPAIGNS_ERROR_MESSAGE, exception.message
    end

    test "does not check closed campaigns for campaigns limit" do
      (SecurityCampaigns::MAX_CAMPAIGNS_COUNT - 1).times do
        create(:security_campaign, organization: @org)
      end

      create(:security_campaign, organization: @org, closed_at: Time.now)

      assert_changes -> { SecurityCampaigns::SecurityCampaign.count }, 1 do
        CreationService.call(campaign: @campaign, logical_alert_info: @logical_alert_info, actor: @current_user, query_string: @query_string)
      end
    end
  end
end
