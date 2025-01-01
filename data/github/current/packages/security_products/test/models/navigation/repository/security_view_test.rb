# typed: true
# frozen_string_literal: true

require "test_helper"

class NavigationRepositorySecurityViewTest < GitHub::TestCase
  include DependabotAlertsEnterpriseEnablementHelper

  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?

    @user = create(:user)
    @priv_repo = create(:private_repository, owner: @user)
    @public_repository = create(:repository, owner: @user)

    @org = create(:business_plus_organization, admin: @user)
    @org_repo = create(:repository, owner: @org)
    @priv_org_repo = create(:private_repository, owner: @org)
    @public_org_repo = create(:public_repository, owner: @org)

    @random_user = create(:user)
  end

  setup do
    GitHub::Turboscan.stubs(:severities_for_org).returns(Twirp::ClientResp.new(data: Turboscan::Proto::SeveritiesForOrgResponse.new))
    GitHub.flipper[:security_campaigns_read_without_alerts_limit].disable

    if GitHub.enterprise?
      GitHub.stubs(:code_scanning_enabled?).returns(true)
      @public_org_repo.enable_advanced_security!(actor: @user)
    end
  end

  context "#security_count" do
    test "includes the dependency alert count" do
      # Ensure that in GHES, all necesssary prerequisites are enabled:
      stub_dependabot_alerts_enterprise_enablement if GitHub.enterprise?

      # Ensure that the repository has alerts enabled:
      @org_repo.enable_vulnerability_alerts(actor: @org_repo.owner)

      create(:repository_vulnerability_alert, repository: @org_repo)

      view = Navigation::Repository::SecurityView.new(current_user: nil, current_repository: @org_repo)
      assert_equal 0, view.security_count

      view = Navigation::Repository::SecurityView.new(current_user: @user, current_repository: @org_repo)
      assert_equal 1, view.security_count
    end

    test "includes the published advisory count", skip_enterprise: true do
      create(:published_repository_advisory, repository: @org_repo)

      view = Navigation::Repository::SecurityView.new(current_user: nil, current_repository: @org_repo)
      assert_equal 1, view.security_count

      view = Navigation::Repository::SecurityView.new(current_user: @user, current_repository: @org_repo)
      assert_equal 1, view.security_count
    end

    test "includes the token scanning alert count while backfill is in progess but an incremental record exists" do
      Repository::TokenScanningDependency::TokenScanningServiceUnresolvedCache.any_instance.stubs(:count).returns(1)

      Repository.any_instance.stubs(:content_analysis_enabled?).returns(true)
      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @priv_org_repo.enable_advanced_security!(actor: @user)
      SecretScanning::Features::Repo::TokenScanning.new(@priv_org_repo).enable(actor: @user)

      TokenScanStatus.ensure_status_entry_for_repo!(@priv_org_repo)
      view = Navigation::Repository::SecurityView.new(current_user: @user, current_repository: @priv_org_repo)
      assert_equal 1, view.security_count
    end

    test "token scanning alert count filters out ignored tokens" do
      Repository.any_instance.stubs(:content_analysis_enabled?).returns(true)
      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @priv_org_repo.enable_advanced_security!(actor: @user)
      SecretScanning::Features::Repo::TokenScanning.new(@priv_org_repo).enable(actor: @user)

      token = create(:token_scan_result, repository: @priv_org_repo)
      location = create(:token_scan_result_location,
        repository_id: @priv_org_repo.id,
        token_scan_result_id: token.id,
        commit_oid: "4b6472266afd7b471e86085a6659e8c7f2b119da",
        blob_oid: "7d7d5bd91e0039acffb385ea92f48ad18d92e788",
        ignore_token: true
      )

      view = Navigation::Repository::SecurityView.new(current_user: @user, current_repository: @priv_org_repo)
      assert_equal 0, view.security_count
    end

    test "includes the token scanning alert count when backfill scan is completed" do
      Repository.any_instance.stubs(:content_analysis_enabled?).returns(true)
      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @priv_org_repo.enable_advanced_security!(actor: @user)
      SecretScanning::Features::Repo::TokenScanning.new(@priv_org_repo).enable(actor: @user)
      Repository::TokenScanningDependency::TokenScanningServiceUnresolvedCache.any_instance.stubs(:count).returns(1)

      TokenScanStatus.ensure_status_entry_for_repo!(@priv_org_repo)
      view = Navigation::Repository::SecurityView.new(current_user: nil, current_repository: @priv_org_repo)
      assert_equal 0, view.security_count

      view = Navigation::Repository::SecurityView.new(current_user: @user, current_repository: @priv_org_repo)
      assert_equal 1, view.security_count

      @priv_org_repo.send(:remove_instance_variable, "@token_scanning_service_unresolved_count") if @priv_org_repo.instance_variable_defined?("@token_scanning_service_unresolved_count")
      Repository::TokenScanningDependency::TokenScanningServiceUnresolvedCache.any_instance.stubs(:count).returns(2)

      @priv_org_repo.token_scan_status.update_completed_scan_state!
      view = Navigation::Repository::SecurityView.new(current_user: @user, current_repository: @priv_org_repo)
      assert_equal 2, view.security_count
    end

    test "includes the code scanning alert count" do
      GitHub.stubs(:code_scanning_enabled?).returns(true)
      GitHub::Turboscan::ManagedAnalyses.expects(:get_managed_analysis_info).at_least(0).returns(nil)
      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @priv_org_repo.enable_advanced_security!(actor: @user)
      VCR.use_cassette("code-scanning/index", persist_with: :turboscan) do
        view = Navigation::Repository::SecurityView.new(current_user: nil, current_repository: @priv_org_repo)
        assert_equal 0, view.security_count

        view = Navigation::Repository::SecurityView.new(current_user: @user, current_repository: @priv_org_repo)
        assert_equal 8, view.security_count
      end
    end
  end


  context "#security_network_alerts_count" do
    test "returns the number of alerts on the repository" do
      # Ensure that in GHES, all necesssary prerequisites are enabled:
      stub_dependabot_alerts_enterprise_enablement if GitHub.enterprise?

      # Ensure vulnerability alerts are enabled:
      @priv_repo.enable_vulnerability_alerts(actor: @user)

      # Create an alert for the repo:
      create(:repository_vulnerability_alert, { repository: @priv_repo })

      view = Navigation::Repository::SecurityView.new(current_user: @user, current_repository: @priv_repo)
      assert_equal 1, view.security_network_alerts_count
    end

    test "returns 0 if the repository has vulnerability alerts disabled" do
      # Create an alert for the repo:
      create(:repository_vulnerability_alert, { repository: @priv_repo })

      # Then disable vulnerability alerts:
      @priv_repo.disable_vulnerability_alerts(actor: @user)

      # And now expect
      view = Navigation::Repository::SecurityView.new(current_user: @user, current_repository: @priv_repo)
      assert_equal 0, view.security_network_alerts_count
    end
  end

  context "#show_code_scanning?" do
    test "return true for owner of public dotcom repositories", skip_enterprise: true, skip_with_all_emus: true do
      view = Navigation::Repository::SecurityView.new(current_user: @user, current_repository: @public_repository)
      assert view.show_code_scanning?
    end

    test "return false for someone with no access to public dotcom repositories", skip_enterprise: true, skip_with_all_emus: true do
      view = Navigation::Repository::SecurityView.new(current_user: @random_user, current_repository: @public_repository)
      refute view.show_code_scanning?
    end

    test "return false if advanced security not purchased" do
      view = Navigation::Repository::SecurityView.new(current_user: @user, current_repository: @priv_org_repo)
      refute view.show_code_scanning?
    end

    test "return true if advanced security purchased and enabled" do
      view = Navigation::Repository::SecurityView.new(current_user: @user, current_repository: @priv_org_repo)
      if GitHub.enterprise?
        GitHub.stubs(:code_scanning_enabled?).returns(true)
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      else
        @org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      end
      @priv_org_repo.enable_advanced_security!(actor: @user)
      assert view.show_code_scanning?
    end
  end

  context "#show_security_campaigns?" do
    test "return true when campaigns enabled and there are security campaigns for this repository" do
      GitHub.flipper[:security_campaigns].enable
      GitHub.flipper[:security_campaigns_disable].disable

      enable_code_scanning!
      @priv_org_repo.add_member(@user, action: :write)

      create(:security_campaign_alert, repository: @priv_org_repo)

      view = Navigation::Repository::SecurityView.new(current_user: @user, current_repository: @priv_org_repo)
      assert view.show_security_campaigns?
    end

    test "return true when campaigns enabled, there are security campaigns for this repository and the repository is public", skip_with_all_emus: true do
      GitHub.flipper[:security_campaigns].enable
      GitHub.flipper[:security_campaigns_disable].disable

      create(:security_campaign_alert, repository: @public_org_repo)

      view = Navigation::Repository::SecurityView.new(current_user: @user, current_repository: @public_org_repo)
      assert view.show_security_campaigns?
    end

    test "return false when feature flag is disabled and there are security campaigns for this repository" do
      GitHub.flipper[:security_campaigns].disable

      enable_code_scanning!
      @priv_org_repo.add_member(@user, action: :write)

      create(:security_campaign_alert, repository: @priv_org_repo)

      view = Navigation::Repository::SecurityView.new(current_user: @user, current_repository: @priv_org_repo)
      refute view.show_security_campaigns?
    end

    test "return false when disable feature flag is enabled and there are security campaigns for this repository" do
      GitHub.flipper[:security_campaigns].enable
      GitHub.flipper[:security_campaigns_disable].enable(@priv_org_repo.owner)

      enable_code_scanning!
      @priv_org_repo.add_member(@user, action: :write)

      create(:security_campaign_alert, repository: @priv_org_repo)

      view = Navigation::Repository::SecurityView.new(current_user: @user, current_repository: @priv_org_repo)
      refute view.show_security_campaigns?
    end

    test "return false when campaigns enabled and there are no open security campaigns for this repository" do
      GitHub.flipper[:security_campaigns].enable

      enable_code_scanning!
      @priv_org_repo.add_member(@user, action: :write)

      security_campaign_1 = create(:security_campaign, organization: @org, closed_at: Time.now)
      create(:security_campaign_alert, repository: @priv_org_repo, security_campaign: security_campaign_1)

      view = Navigation::Repository::SecurityView.new(current_user: @user, current_repository: @priv_org_repo)
      refute view.show_security_campaigns?
    end
  end

  context "#security_campaigns" do
    test "return all open security campaigns" do
      security_campaign_1 = create(:security_campaign, organization: @org)
      create(:security_campaign_alert, repository: @priv_org_repo, security_campaign: security_campaign_1)
      security_campaign_2 = create(:security_campaign, organization: @org)
      create(:security_campaign_alert, repository: @priv_org_repo, security_campaign: security_campaign_2)
      security_campaign_3 = create(:security_campaign, organization: @org, ends_at: 1.week.ago)
      create(:security_campaign_alert, repository: @priv_org_repo, security_campaign: security_campaign_3)
      create(:security_campaign, organization: @org)
      security_campaign_4 = create(:security_campaign, organization: @org, ends_at: 1.week.ago, closed_at: Time.now)
      create(:security_campaign_alert, repository: @priv_org_repo, security_campaign: security_campaign_4)

      view = Navigation::Repository::SecurityView.new(current_user: @user, current_repository: @priv_org_repo)
      assert_equal [security_campaign_1, security_campaign_2, security_campaign_3], view.security_campaigns.sort_by(&:id)
    end

    test "return all open security campaigns when security_campaigns_read_without_alerts_limit flag is enabled" do
      GitHub.flipper[:security_campaigns_read_without_alerts_limit].enable

      open_campaigns = create_list(:security_campaign, 3, organization: @org)
      closed_campaign = create(:security_campaign, organization: @org, ends_at: 1.week.ago, closed_at: Time.now)

      GitHub::Turboscan.expects(:counts_by_campaigns).once.with({
        owner_ids: [@org.id],
        security_campaign_ids: open_campaigns.map(&:id),
        repository_ids: [@priv_org_repo.id],
      }).returns(Struct.new(:data).new(
        data: Turboscan::Proto::CountsByCampaignsResponse.new({
          campaign_counts: open_campaigns.map do |campaign|
            {
              campaign_id: campaign.id,
              open_count: 3,
              closed_count: 2,
              open_with_links_count: 1,
            }
          end
        })
      ))
      view = Navigation::Repository::SecurityView.new(current_user: @user, current_repository: @priv_org_repo)
      assert_equal open_campaigns, view.security_campaigns.sort_by(&:id)
    end
  end

  context "#split_secret_scanning_count?" do
    test "returns false when generic secrets is not available and NPP is not available" do
      SecretScanning::Features::Repo::GenericSecrets.any_instance.stubs(:feature_available?).returns(false)
      SecretScanning::Features::Repo::LowerConfidencePatterns.any_instance.stubs(:feature_available?).returns(false)

      view = Navigation::Repository::SecurityView.new(current_user: @user, current_repository: @public_repository)

      refute view.split_secret_scanning_count?
    end

    test "returns true if generic secrets or NPP is avilable" do
      SecretScanning::Features::Repo::GenericSecrets.any_instance.stubs(:feature_available?).returns(true)
      SecretScanning::Features::Repo::LowerConfidencePatterns.any_instance.stubs(:feature_available?).returns(false)

      view = Navigation::Repository::SecurityView.new(current_user: @user, current_repository: @priv_org_repo)

      assert view.split_secret_scanning_count?
    end
  end

  context "#security_token_scanning_count_experimental" do
    test "gets count by conf from cache" do
      Repository::TokenScanningDependency::TokenScanningServiceUnresolvedCache
        .any_instance
        .stubs(:count_for_results_category)
        .with do |arg|
          arg == :experimental
        end
        .returns(3)

      view = Navigation::Repository::SecurityView.new(current_user: @user, current_repository: @priv_org_repo)

      assert_equal 3, view.security_token_scanning_count_experimental
    end

    test "returns 0 when count is less than 0" do
      Repository::TokenScanningDependency::TokenScanningServiceUnresolvedCache
        .any_instance
        .stubs(:count_for_results_category)
        .with do |arg|
          arg == :experimental
        end
        .returns(-1)

      view = Navigation::Repository::SecurityView.new(current_user: @user, current_repository: @priv_org_repo)

      assert_equal 0, view.security_token_scanning_count_experimental
    end
  end

  context "#security_token_scanning_count_default" do
    test "gets count by conf from cache" do
      Repository::TokenScanningDependency::TokenScanningServiceUnresolvedCache
        .any_instance
        .stubs(:count_for_results_category)
        .with do |arg|
          arg == :default
        end
        .returns(3)

      view = Navigation::Repository::SecurityView.new(current_user: @user, current_repository: @priv_org_repo)

      assert_equal 3, view.security_token_scanning_count_default
    end

    test "returns 0 when count is less than 0" do
      Repository::TokenScanningDependency::TokenScanningServiceUnresolvedCache
        .any_instance
        .stubs(:count_for_results_category)
        .with do |arg|
          arg == :default
        end
        .returns(-1)

      view = Navigation::Repository::SecurityView.new(current_user: @user, current_repository: @priv_org_repo)

      assert_equal 0, view.security_token_scanning_count_default
    end
  end

  private

  def enable_code_scanning!
    if GitHub.enterprise?
      GitHub.stubs(:actions_enabled?).returns(true)
      GitHub.stubs(:code_scanning_enabled?).returns(true)
    else
      @org.advanced_security_billable_entity.mark_advanced_security_as_purchased_for_entity(actor: @user)
    end
    @priv_org_repo.enable_advanced_security!(actor: @user)
  end
end
