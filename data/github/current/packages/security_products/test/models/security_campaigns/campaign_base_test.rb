# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityCampaigns::CampaignBaseTest < GitHub::TestCase
  fixtures do
    @org1 = create(:organization)
    @org2 = create(:organization)
    @org3 = create(:organization)

    @repo1 = create(:private_repository, from_example: :repository_test_simple, owner: @org1)
    @repo2 = create(:private_repository, from_example: :repository_test_simple, owner: @org2)
    @repo3 = create(:private_repository, from_example: :repository_test_simple, owner: @org3)

    @campaign1 = create(:security_campaign, name: "Campaign1", organization: @org1)
    @campaign2 = create(:security_campaign, name: "Campaign2", organization: @org2)

    @alert11 = create(:security_campaign_alert, repository: @repo1, security_campaign: @campaign1, logical_alert_number: 1)
    @alert12 = create(:security_campaign_alert, repository: @repo1, security_campaign: @campaign2, logical_alert_number: 2)
    @alert21 = create(:security_campaign_alert, repository: @repo2, security_campaign: @campaign1, logical_alert_number: 3)
    @alert22 = create(:security_campaign_alert, repository: @repo2, security_campaign: @campaign2, logical_alert_number: 4)
    @alert31 = create(:security_campaign_alert, repository: @repo3, security_campaign: @campaign1, logical_alert_number: 5)
    @alert32 = create(:security_campaign_alert, repository: @repo3, security_campaign: @campaign2, logical_alert_number: 6)

  end

  test "filter_campaign_alerts filters out alerts from other orgs" do
    filtered_alerts =
      SecurityCampaigns::CampaignBase.filter_campaign_alerts([@campaign1, @campaign2],
        [@alert11, @alert12, @alert21, @alert22, @alert31, @alert32], strategy: nil)

    #  Only alerts that are in their correct orgs are returned
    assert_equal 2, filtered_alerts.size
    alert1 = filtered_alerts.fetch(0)
    alert2 = filtered_alerts.fetch(1)
    assert_equal @alert11.id, alert1.id
    assert_equal @alert22.id, alert2.id
  end

  test "filter_campaign_alerts applies a strategy" do
    # the security center filtering searches against repository_security_center_configs
    create(:repository_security_center_config, repository: @repo1)
    create(:repository_security_center_config, repository: @repo2)
    create(:repository_security_center_config, repository: @repo3)

    alerts_query_service = CodeScanning::AlertQueryService.for_organization(
      user: @org1.admin,
      user_session: create(:user_session, user: @org1.admin),
      organization: @org1,
      query: "is:open repo:#{@repo1.name_with_display_owner}",
    )

    filtered_alerts =
      SecurityCampaigns::CampaignBase.filter_campaign_alerts([@campaign1, @campaign2],
        [@alert11, @alert12, @alert21, @alert22, @alert31, @alert32], strategy: alerts_query_service.strategy)

    #  Only alerts that are in their correct orgs are returned
    assert_equal 1, filtered_alerts.size
    alert1 = filtered_alerts.fetch(0)
    assert_equal @alert11.id, alert1.id
  end

  test "filter_campaign_alerts includes alerts in public repos" do
    public_repo = create(:public_repository, from_example: :repository_test_simple, owner: @org1)
    alert41 = create(:security_campaign_alert, repository: public_repo, security_campaign: @campaign1, logical_alert_number: 7)

    filtered_alerts =
      SecurityCampaigns::CampaignBase.filter_campaign_alerts([@campaign1, @campaign2],
        [@alert11, @alert12, @alert21, @alert22, @alert31, @alert32, alert41], strategy: nil)

    assert_equal 3, filtered_alerts.size
    assert_equal filtered_alerts.map(&:id).sort, [alert41.id, @alert11.id, @alert22.id].sort
  end
end
