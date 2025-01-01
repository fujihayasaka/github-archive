# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityCampaigns::CampaignWithCountsTest < GitHub::TestCase

  ResponseMock = Struct.new(:data)
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

  context ".load" do
    test "when loading overlapping campaigns the alerts are correctly split" do
      stub_ts_counts_response({ @repo1 => [@a1] })
      stub_ts_counts_response({ @repo1 => [@a1, @a2, @a3] })

      campaigns_for_repo1 = SecurityCampaigns::CampaignWithCounts.load(
        security_campaigns: [@security_campaign1, @security_campaign2],
        repo: @repo1,
        user: @org_admin
      )

      assert_equal 2, campaigns_for_repo1.size
      campaign1 = campaigns_for_repo1.fetch(0)
      campaign2 = campaigns_for_repo1.fetch(1)

      assert_equal @security_campaign1.id, campaign1.id
      assert_equal "Campaign1", campaign1.name_for_display
      assert_equal 1, campaign1.open_count
      assert_equal 0, campaign1.closed_count
      assert_equal 1, campaign1.total_count

      assert_equal @security_campaign2.id, campaign2.id
      assert_equal "Campaign2", campaign2.name_for_display
      assert_equal 3, campaign2.open_count
      assert_equal 0, campaign2.closed_count
      assert_equal 3, campaign2.total_count
    end

    test "when loading campaigns with open an closed alerts they are counted correctly" do
      stub_ts_counts_response({ @repo2 => [@a10, @a20] })
      stub_ts_counts_response({ @repo2 => [@a30, @a40] })
      campaigns_for_repo2 = SecurityCampaigns::CampaignWithCounts.load(
        security_campaigns: [@security_campaign1, @security_campaign2],
        repo: @repo2,
        user: @org_admin
      )

      assert_equal 2, campaigns_for_repo2.size
      campaign1 = campaigns_for_repo2.fetch(0)
      campaign2 = campaigns_for_repo2.fetch(1)

      assert_equal @security_campaign1.id, campaign1.id
      assert_equal "Campaign1", campaign1.name_for_display
      assert_equal 0, campaign1.open_count
      assert_equal 2, campaign1.closed_count
      assert_equal 2, campaign1.total_count

      assert_equal @security_campaign2.id, campaign2.id
      assert_equal "Campaign2", campaign2.name_for_display
      assert_equal 1, campaign2.open_count
      assert_equal 1, campaign2.closed_count
      assert_equal 2, campaign2.total_count
    end

    test "loading full campaigns with multiple repositories in each" do
      stub_ts_counts_response({ @repo1 => [@a1], @repo2 => [@a10, @a20] })
      stub_ts_counts_response({ @repo1 => [@a1, @a2, @a3], @repo2 => [@a30, @a40] })
      campaigns = SecurityCampaigns::CampaignWithCounts.load(security_campaigns: [@security_campaign1, @security_campaign2], user: @org_admin)

      assert_equal 2, campaigns.size
      campaign1 = campaigns.fetch(0)
      campaign2 = campaigns.fetch(1)

      assert_equal @security_campaign1.id, campaign1.id
      assert_equal "Campaign1", campaign1.name_for_display
      assert_equal 1, campaign1.open_count
      assert_equal 2, campaign1.closed_count
      assert_equal 3, campaign1.total_count

      assert_equal @security_campaign2.id, campaign2.id
      assert_equal "Campaign2", campaign2.name_for_display
      assert_equal 4, campaign2.open_count
      assert_equal 1, campaign2.closed_count
      assert_equal 5, campaign2.total_count
    end

    test "overlapping logical numbers " do
      repo1 = create(:private_repository, from_example: :repository_test_simple, owner: @org)
      repo2 = create(:private_repository, from_example: :repository_test_simple, owner: @org)

      campaign1 = create(:security_campaign, name: "Campaign1", organization: @org)
      campaign2 = create(:security_campaign, name: "Campaign2", organization: @org)

      alert1 = create(:security_campaign_alert, repository: repo1, security_campaign: campaign1, logical_alert_number: 1)
      alert2 = create(:security_campaign_alert, repository: repo2, security_campaign: campaign2, logical_alert_number: 1)

      stub_ts_counts_response({ repo1 => [@a1] })
      stub_ts_counts_response({  repo2 => [@a1] })
      campaigns_with_alert1, campaigns_with_alert2 = SecurityCampaigns::CampaignWithCounts.load(security_campaigns: [campaign1, campaign2], user: @org_admin)

      assert_equal 1, campaigns_with_alert1&.open_count
      assert_equal 1, campaigns_with_alert2&.open_count
    end

    test "loading campaigns with open and closed alerts they are counted correctly when security_campaigns_read_without_alerts_limit is enabled" do
      GitHub.flipper[:security_campaigns_read_without_alerts_limit].enable

      stub_ts_counts_by_campaigns_response(security_campaign_ids: [@security_campaign1.id, @security_campaign2.id])

      campaigns_for_repo2 = SecurityCampaigns::CampaignWithCounts.load(
        security_campaigns: [@security_campaign1, @security_campaign2],
        user: @org_admin
      )

      assert_equal 2, campaigns_for_repo2.size
      campaign1 = campaigns_for_repo2.fetch(0)
      campaign2 = campaigns_for_repo2.fetch(1)

      assert_equal @security_campaign1.id, campaign1.id
      assert_equal "Campaign1", campaign1.name_for_display
      assert_equal 3, campaign1.open_count
      assert_equal 2, campaign1.closed_count
      assert_equal 5, campaign1.total_count

      assert_equal @security_campaign2.id, campaign2.id
      assert_equal "Campaign2", campaign2.name_for_display
      assert_equal 3, campaign2.open_count
      assert_equal 2, campaign2.closed_count
      assert_equal 5, campaign2.total_count
    end

    test "loading campaigns with open an closed alerts they are counted correctly when repo ids are given and security_campaigns_read_without_alerts_limit is enabled" do
      GitHub.flipper[:security_campaigns_read_without_alerts_limit].enable

      stub_ts_counts_by_campaigns_response(
        security_campaign_ids: [@security_campaign1.id, @security_campaign2.id],
        repository_ids: [@repo2.id]
      )

      campaigns_for_repo2 = SecurityCampaigns::CampaignWithCounts.load(
        security_campaigns: [@security_campaign1, @security_campaign2],
        repo: @repo2,
        user: @org_admin
      )

      assert_equal 2, campaigns_for_repo2.size
      campaign1 = campaigns_for_repo2.fetch(0)
      campaign2 = campaigns_for_repo2.fetch(1)

      assert_equal @security_campaign1.id, campaign1.id
      assert_equal "Campaign1", campaign1.name_for_display
      assert_equal 3, campaign1.open_count
      assert_equal 2, campaign1.closed_count
      assert_equal 5, campaign1.total_count

      assert_equal @security_campaign2.id, campaign2.id
      assert_equal "Campaign2", campaign2.name_for_display
      assert_equal 3, campaign2.open_count
      assert_equal 2, campaign2.closed_count
      assert_equal 5, campaign2.total_count
    end

    test "returns 0 counts when counts by campaigns fail when security_campaigns_read_without_alerts_limit is enabled" do
      GitHub.flipper[:security_campaigns_read_without_alerts_limit].enable

      GitHub::Turboscan.expects(:counts_by_campaigns).once.with({
        owner_ids: [@org.id],
        security_campaign_ids: [@security_campaign1.id, @security_campaign2.id],
      }).returns(ResponseMock.new(data: nil))

      campaigns_for_repo2 = SecurityCampaigns::CampaignWithCounts.load(
        security_campaigns: [@security_campaign1, @security_campaign2],
        user: @org_admin
      )

      assert_equal 2, campaigns_for_repo2.size
      campaign1 = campaigns_for_repo2.fetch(0)
      campaign2 = campaigns_for_repo2.fetch(1)

      assert_equal @security_campaign1.id, campaign1.id
      assert_equal "Campaign1", campaign1.name_for_display
      assert_equal 0, campaign1.open_count
      assert_equal 0, campaign1.closed_count
      assert_equal 0, campaign1.total_count

      assert_equal @security_campaign2.id, campaign2.id
      assert_equal "Campaign2", campaign2.name_for_display
      assert_equal 0, campaign2.open_count
      assert_equal 0, campaign2.closed_count
      assert_equal 0, campaign2.total_count
    end
  end

  context ".for_repo_with_alerts" do
    test "returns campaigns counts for campaigns with alerts only" do
      GitHub::Turboscan.expects(:counts_by_campaigns).once.with({
        owner_ids: [@org.id],
        security_campaign_ids: [@security_campaign1.id, @security_campaign2.id, @empty_campaign.id],
        repository_ids: [@repo1.id],
      }).returns(Struct.new(:data).new(
        data: Turboscan::Proto::CountsByCampaignsResponse.new({
          campaign_counts: [
            {
              campaign_id: @security_campaign1.id,
              open_count: 3,
              closed_count: 2,
              open_with_links_count: 1,
            },
            {
              campaign_id: @security_campaign2.id,
              open_count: 2,
              closed_count: 2,
              open_with_links_count: 1,
            },
          ]
        })
      ))
      campaigns_with_alert1, campaigns_with_alert2 = SecurityCampaigns::CampaignWithCounts.for_repo_with_alerts(
        security_campaigns: [@security_campaign1, @security_campaign2, @empty_campaign],
        repo: @repo1,
      )
      assert_equal 3, campaigns_with_alert1&.open_count
      assert_equal 2, campaigns_with_alert2&.open_count
    end
  end

  context ".for_repo_and_alert_number" do
    test "returns campaigns counts for campaigns with given alert" do
      alert_number = 1
      GitHub::Turboscan.expects(:counts_by_campaigns).once.with({
        owner_ids: [@org.id],
        security_campaign_ids: [@security_campaign1.id, @security_campaign2.id, @empty_campaign.id],
        repository_ids: [@repo1.id],
        filter: {
          repo_numbers: [
            Turboscan::Proto::RepoNumber.new(
              repository_id: @repo1.id,
              number: alert_number,
            )
          ]
        }
      }).returns(Struct.new(:data).new(
        data: Turboscan::Proto::CountsByCampaignsResponse.new({
          campaign_counts: [
            {
              campaign_id: @security_campaign1.id,
              open_count: 3,
              closed_count: 2,
              open_with_links_count: 1,
            },
            {
              campaign_id: @security_campaign2.id,
              open_count: 2,
              closed_count: 2,
              open_with_links_count: 1,
            },
          ]
        })
      ))

      campaigns_with_alert1, campaigns_with_alert2 = SecurityCampaigns::CampaignWithCounts.for_repo_and_alert_number(
        security_campaigns: [@security_campaign1, @security_campaign2, @empty_campaign],
        repo: @repo1,
        alert_number:,
      )
      assert_equal 3, campaigns_with_alert1&.open_count
      assert_equal 2, campaigns_with_alert2&.open_count
    end
  end

  def stub_ts_counts_response(repo_alerts_map)
    repo_numbers = []
    open_count = 0
    closed_count = 0
    repo_alerts_map.each do |repo, alerts|
      alerts.each do |alert|
        repo_numbers.append(
          Turboscan::Proto::RepoNumber.new(
            repository_id: repo.id,
            number: alert.number,
          )
        )
        if !alert.is_fixed && (alert.resolution.nil? || alert.resolution == :NO_RESOLUTION)
          open_count += 1
        else
          closed_count += 1
        end
      end
    end

    GitHub::Turboscan.expects(:counts_by_repo_numbers).once.with({
      owner_ids: [@org.id],
      repo_numbers: repo_numbers,
    }).returns(ResponseMock.new(
      data: Turboscan::Proto::CountsByRepoNumbersResponse.new({
        open_count: open_count,
        closed_count: closed_count,
      })
    ))
  end

  def stub_ts_counts_by_campaigns_response(security_campaign_ids:, repository_ids: nil)
    GitHub::Turboscan.expects(:counts_by_campaigns).once.with({
      owner_ids: [@org.id],
      security_campaign_ids:,
      repository_ids:,
    }.compact).returns(ResponseMock.new(
      data: Turboscan::Proto::CountsByCampaignsResponse.new({
        campaign_counts: security_campaign_ids.map do |campaign_id|
          {
            campaign_id:,
            open_count: 3,
            closed_count: 2,
            open_with_links_count: 1,
          }
        end
      })
    ))
  end
end
