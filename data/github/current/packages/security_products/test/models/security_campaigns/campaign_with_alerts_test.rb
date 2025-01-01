# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityCampaigns::CampaignWithAlertsTest < GitHub::TestCase
  include ::SecurityCenter::TurboscanTestSetup

  setup do
    @org_admin = create(:user)
    @user_session = create(:user_session, user: @org_admin)

    @org = create(:organization, admins: [@org_admin])
    @repo1 = create(:private_repository, from_example: :repository_test_simple, owner: @org)
    @repo2 = create(:private_repository, from_example: :repository_test_simple, owner: @org)

    @security_campaign1 = create(:security_campaign, name: "Campaign1", organization: @org)
    @security_campaign2 = create(:security_campaign, name: "Campaign2", organization: @org)
    @empty_campaign = create(:security_campaign, name: "Empty campaign", organization: @org)

    # Add alerts for both repos on both campaigns
    create(:security_campaign_alert, repository: @repo1, security_campaign: @security_campaign1, logical_alert_number: 1)
    create(:security_campaign_alert, repository: @repo2, security_campaign: @security_campaign1, logical_alert_number: 10)
    create(:security_campaign_alert, repository: @repo2, security_campaign: @security_campaign1, logical_alert_number: 20)

    create(:security_campaign_alert, repository: @repo1, security_campaign: @security_campaign2, logical_alert_number: 1)
    create(:security_campaign_alert, repository: @repo1, security_campaign: @security_campaign2, logical_alert_number: 2)
    create(:security_campaign_alert, repository: @repo1, security_campaign: @security_campaign2, logical_alert_number: 3)
    create(:security_campaign_alert, repository: @repo2, security_campaign: @security_campaign2, logical_alert_number: 30)
    create(:security_campaign_alert, repository: @repo2, security_campaign: @security_campaign2, logical_alert_number: 40)

    @a1 = Turboscan::Proto::Result.new(number: 1)
    @a2 = Turboscan::Proto::Result.new(number: 2)
    @a3 = Turboscan::Proto::Result.new(number: 3)
    @a10 = Turboscan::Proto::Result.new(number: 10, is_fixed: true)
    @a20 = Turboscan::Proto::Result.new(number: 20, resolution: :USED_IN_TESTS)
    @a30 = Turboscan::Proto::Result.new(number: 30, is_fixed: true, resolution: :USED_IN_TESTS)
    @a40 = Turboscan::Proto::Result.new(number: 40)

    GitHub.flipper[:security_campaigns_read_without_alerts_limit].disable
  end

  test "loading a campaign" do
    stub_ts_alerts_response(@security_campaign2.security_campaign_alerts.where(repository: @repo1), { @repo1 => [@a1] }, open_count: 4, resolved_count: 10, next_cursor: "cursor1")

    campaign = SecurityCampaigns::CampaignWithAlerts.load_campaign(
      @security_campaign2, repo: @repo1, user: @org_admin, user_session: @user_session)

    assert_equal @security_campaign2.id, campaign.id
    assert_equal @security_campaign2.number, campaign.number
    assert_equal "Campaign2", campaign.name_for_display
    assert_equal 4, campaign.open_count
    assert_equal 10, campaign.closed_count
    assert_equal 14, campaign.total_count
    assert_equal 1, campaign.turboscan_alerts.size
    assert_equal "cursor1", campaign.next_cursor
  end

  test "loading a campaign with an after cursor" do
    stub_ts_alerts_response(@security_campaign2.security_campaign_alerts.where(repository: @repo1), { @repo1 => [@a2] }, open_count: 4, resolved_count: 10, after_cursor: "cursor1", next_cursor: "cursor2", prev_cursor: "cursor0")

    campaign = SecurityCampaigns::CampaignWithAlerts.load_campaign(
      @security_campaign2, repo: @repo1, user: @org_admin, user_session: @user_session, after_cursor: "cursor1")

    assert_equal 4, campaign.open_count
    assert_equal 10, campaign.closed_count
    assert_equal 14, campaign.total_count
    assert_equal 1, campaign.turboscan_alerts.size
    assert_equal "cursor2", campaign.next_cursor
    assert_equal "cursor0", campaign.prev_cursor
  end

  test "loading a campaign with a before cursor" do
    stub_ts_alerts_response(@security_campaign2.security_campaign_alerts.where(repository: @repo1), { @repo1 => [@a2] }, open_count: 4, resolved_count: 10, before_cursor: "cursor1")

    campaign = SecurityCampaigns::CampaignWithAlerts.load_campaign(
      @security_campaign2, repo: @repo1, user: @org_admin, user_session: @user_session, before_cursor: "cursor1")

    assert_equal 4, campaign.open_count
    assert_equal 10, campaign.closed_count
    assert_equal 14, campaign.total_count
    assert_equal 1, campaign.turboscan_alerts.size
  end

  test "loading a campaign with given alert numbers" do
    alerts = @security_campaign2.security_campaign_alerts.where(repository: @repo1, logical_alert_number: @a2.number).or(@security_campaign2.security_campaign_alerts.where(repository: @repo2, logical_alert_number: @a30.number))

    stub_ts_alerts_response(alerts, { @repo1 => [@a2], @repo2 => [@a30] }, open_count: 1, resolved_count: 1)

    campaign = SecurityCampaigns::CampaignWithAlerts.load_campaign(
      @security_campaign2, user: @org_admin, user_session: @user_session, alert_numbers: { @repo1.id => [@a2.number], @repo2.id => [@a30.number] })

    assert_equal 1, campaign.open_count
    assert_equal 1, campaign.closed_count
    assert_equal 2, campaign.total_count
    assert_equal 2, campaign.turboscan_alerts.size
  end

  test "loading a campaign with alert numbers in public repo" do
    public_repo = create(:public_repository, from_example: :repository_test_simple, owner: @org)
    create(:security_campaign_alert, repository: public_repo, security_campaign: @security_campaign2, logical_alert_number: 7)
    alert7 = Turboscan::Proto::Result.new(number: 7)

    alerts = @security_campaign2.security_campaign_alerts.where(repository: @repo1, logical_alert_number: @a2.number)
      .or(@security_campaign2.security_campaign_alerts.where(repository: @repo2, logical_alert_number: @a30.number))
      .or(@security_campaign2.security_campaign_alerts.where(repository: public_repo, logical_alert_number: alert7.number))

    stub_ts_alerts_response(alerts, { @repo1 => [@a2], @repo2 => [@a30], public_repo => [alert7] }, open_count: 2, resolved_count: 1)

    campaign = SecurityCampaigns::CampaignWithAlerts.load_campaign(
      @security_campaign2, user: @org_admin, user_session: @user_session, alert_numbers: { @repo1.id => [@a2.number], @repo2.id => [@a30.number], public_repo.id => [alert7.number] })

    assert_equal 2, campaign.open_count
    assert_equal 1, campaign.closed_count
    assert_equal 3, campaign.total_count
    assert_equal 3, campaign.turboscan_alerts.size
  end

  test "loading a campaign with no alerts do nothing" do
    # Load in org-level context
    campaign = SecurityCampaigns::CampaignWithAlerts.load_campaign(@empty_campaign, user: @org_admin, user_session: @user_session)

    assert_equal @empty_campaign.id, campaign.id
    assert_equal "Empty campaign", campaign.name_for_display
    assert_equal 0, campaign.open_count
    assert_equal 0, campaign.closed_count
    assert_equal 0, campaign.total_count

    # Load in repo-level context
    campaign = SecurityCampaigns::CampaignWithAlerts.load_campaign(@empty_campaign, repo: @repo1, user: @org_admin, user_session: @user_session)

    assert_equal @empty_campaign.id, campaign.id
    assert_equal "Empty campaign", campaign.name_for_display
    assert_equal 0, campaign.open_count
    assert_equal 0, campaign.closed_count
    assert_equal 0, campaign.total_count
  end

  test "Loading a campaign with repos from different orgs filters the alerts away" do
    another_org = create(:organization)
    repo_in_other_org = create(:private_repository, from_example: :repository_test_simple, owner: another_org)

    # Pretend that the campaign has alerts from a repo in another org,
    # e.g. if the repo was transferred and the campaign alerts not removed
    cross_org_campaign = create(:security_campaign, name: "Cross org campaign", organization: @org)

    # Add alerts for both repos on both campaigns
    create(:security_campaign_alert, repository: @repo1, security_campaign: cross_org_campaign, logical_alert_number: 1)
    create(:security_campaign_alert, repository: repo_in_other_org, security_campaign: cross_org_campaign, logical_alert_number: 2)

    stub_ts_alerts_response(cross_org_campaign.security_campaign_alerts.where(repository: @repo1), { @repo1 => [@a1] }, open_count: 8, resolved_count: 9, repository_ids: [])
    campaign = SecurityCampaigns::CampaignWithAlerts.load_campaign(cross_org_campaign, user: @org_admin, user_session: @user_session)

    assert_equal cross_org_campaign.id, campaign.id
    assert_equal "Cross org campaign", campaign.name_for_display
    assert_equal 8, campaign.open_count
    assert_equal 9, campaign.closed_count
    assert_equal 17, campaign.total_count
    assert_equal @repo1.id, campaign.turboscan_alerts.fetch(0).repository.id
  end

  test "loading a campaign when security_campaigns_read_without_alerts_limit flag is enabled" do
    GitHub.flipper[:security_campaigns_read_without_alerts_limit].enable

    stub_ts_alerts_response(
      @security_campaign2.security_campaign_alerts.where(repository: @repo1),
      { @repo1 => [@a2] },
      open_count: 4,
      resolved_count: 10,
      next_cursor: "cursor1",
      security_campaign_ids: [@security_campaign2.id],
      repo_numbers: []
    )

    campaign = SecurityCampaigns::CampaignWithAlerts.load_campaign(
      @security_campaign2, repo: @repo1, user: @org_admin, user_session: @user_session)

    assert_equal @security_campaign2.id, campaign.id
    assert_equal @security_campaign2.number, campaign.number
    assert_equal "Campaign2", campaign.name_for_display
    assert_equal 4, campaign.open_count
    assert_equal 10, campaign.closed_count
    assert_equal 14, campaign.total_count
    assert_equal 1, campaign.turboscan_alerts.size
    assert_equal "cursor1", campaign.next_cursor
  end

  test "loading a campaign with given alert numbers when security_campaigns_read_without_alerts_limit is enabled" do
    GitHub.flipper[:security_campaigns_read_without_alerts_limit].enable

    alerts = @security_campaign2.security_campaign_alerts.where(repository: @repo1, logical_alert_number: @a2.number).or(@security_campaign2.security_campaign_alerts.where(repository: @repo2, logical_alert_number: @a30.number))

    stub_ts_alerts_response(
      alerts,
      { @repo1 => [@a2], @repo2 => [@a30] },
      open_count: 1,
      resolved_count: 1,
      security_campaign_ids: [@security_campaign2.id],
    )

    campaign = SecurityCampaigns::CampaignWithAlerts.load_campaign(
      @security_campaign2, user: @org_admin, user_session: @user_session, alert_numbers: { @repo1.id => [@a2.number], @repo2.id => [@a30.number] })

    assert_equal 1, campaign.open_count
    assert_equal 1, campaign.closed_count
    assert_equal 2, campaign.total_count
    assert_equal 2, campaign.turboscan_alerts.size
  end

  def stub_ts_alerts_response(
    alerts,
    repo_alerts_map,
    open_count: nil,
    resolved_count: nil,
    after_cursor: "",
    before_cursor: "",
    next_cursor: nil,
    prev_cursor: nil,
    repository_ids: nil,
    repo_numbers: nil,
    security_campaign_ids: []
  )
    # We always pass all repo numbers, regardless of the response
    repo_numbers = repo_numbers || alerts.each_with_object([]) do |alert, repo_numbers|
      repo_numbers.append(
        Turboscan::Proto::RepoNumber.new(
          repository_id: alert.repository_id,
          number: alert.logical_alert_number,
        )
      )
    end.sort_by { |rn| [rn.repository_id, rn.number] }

    # This is the response returned by Turboscan
    results = repo_alerts_map.each_with_object([]) do |(repo, alerts), results|
      alerts.each do |alert|
        results.append(Turboscan::Proto::RepoResult.new(
          repository_id: repo.id,
          result: alert
        ))
      end
    end

    if repository_ids.nil?
      repository_ids = if repo_alerts_map.size == 1
        repo_alerts_map.keys.map(&:id)
      else
        []
      end
    end

    GitHub::Turboscan.expects(:alerts_by_repo).once.with(@default_alerts_by_repo_args.merge({
      owner_ids: [@org.id],
      repository_ids:,
      repo_numbers: repo_numbers.map(&:to_h),
      security_campaign_ids:,
      limit: SecurityCampaigns::CampaignWithAlerts::page_size,
      after_cursor:,
      before_cursor:,
    })).returns(Twirp::ClientResp.new(
      data: Turboscan::Proto::AlertsByRepoResponse.new({
        results:,
        open_count:,
        resolved_count:,
        next_cursor:,
        prev_cursor:,
      })
    ))
  end
end
