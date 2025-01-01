# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityCampaignsRepositoriesControllerTest < GitHub::IntegrationTestCase
  include FineGrainedPermissionsTestHelper

  fixtures do
    @user = create(:user)
    @unauthed_user = create(:user, skip_enterprise_managed_user: true)

    @org = create(:business_plus_organization, admin: @user)
    @org.advanced_security_billable_entity&.mark_advanced_security_as_purchased_for_entity(actor: @user)

    @repo = create(:private_repository, from_example: :simple, owner: @org)

    @security_campaign = create(:security_campaign, :with_alerts, organization: @org)

    create(:security_campaign_alert, repository: @repo, security_campaign: @security_campaign, logical_alert_number: 5)
    create(:security_campaign_alert, repository: @repo, security_campaign: @security_campaign, logical_alert_number: 9)
  end

  setup do
    GitHub.flipper[:security_campaigns].enable

    if GitHub.enterprise?
      GitHub.stubs(:actions_enabled?).returns(true)
      GitHub.stubs(:code_scanning_enabled?).returns(true)
    else
      @org.advanced_security_billable_entity.mark_advanced_security_as_purchased_for_entity(actor: @user)
    end

    @repo.enable_advanced_security!(actor: @user)
  end

  context "#show" do
    test "returns successfully when user has write access to repo" do
      as @user
      get "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}", params: {}, xhr: true

      assert_response_success
    end

    test "returns successfully when repo is internal" do
      biz = create(:global_business)
      org = create(:business_plus_organization, business: biz)
      org.add_admin(@user)
      biz.advanced_security_billable_entity.mark_advanced_security_as_purchased_for_entity(actor: @user) unless GitHub.enterprise?

      internal_repo = create(:internal_repository, from_example: :simple, owner: org)
      internal_repo.enable_advanced_security!(actor: @user)

      security_campaign = create(:security_campaign, :with_alerts, organization: org)
      create(:security_campaign_alert, repository: internal_repo, security_campaign: security_campaign, logical_alert_number: 5)

      as @user
      get "/#{internal_repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}", params: {}, xhr: true

      assert_response_success
    end

    test "returns 404 when campaign is closed" do
      @security_campaign.update(closed_at: Time.now)

      as @user
      get "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}", params: {}, xhr: true

      assert_response_not_found
    end

    test "returns 404 when feature flag is disabled" do
      GitHub.flipper[:security_campaigns].disable

      as @user
      get "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}", params: {}, xhr: true

      assert_response_not_found
    end

    test "returns 404 when advanced security is disabled" do
      @repo.disable_advanced_security!(actor: @user)

      as @user
      get "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}", params: {}, xhr: true

      assert_response_not_found
    end

    test "returns 404 when user only has read access to repo" do
      readonly_collaborator = create(:user)
      @repo.add_member(readonly_collaborator, action: :read)

      as readonly_collaborator
      get "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}", params: {}, xhr: true

      assert_response_not_found
    end

    test "returns 404 when repo is public", skip_with_all_emus: true do
      public_repo = create(:public_repository, from_example: :simple, owner: @org)
      create(:security_campaign_alert, repository: public_repo, security_campaign: @security_campaign, logical_alert_number: 5)

      as @user
      get "/#{public_repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}", params: {}, xhr: true

      assert_response_not_found
    end

    test "returns 404 when user only has read access to code scanning" do
      readonly_collaborator = create(:user)
      @repo.add_member(readonly_collaborator, action: :read)
      grant_custom_role(user: readonly_collaborator, target: @repo, fgps: [:read_code_scanning])

      as readonly_collaborator
      get "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}", params: {}, xhr: true

      assert_response_not_found
    end

    test "returns 200 when user only has write access to code scanning" do
      readonly_collaborator = create(:user)
      @repo.add_member(readonly_collaborator, action: :read)
      grant_custom_role(user: readonly_collaborator, target: @repo, fgps: [:write_code_scanning])

      as readonly_collaborator
      get "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}", params: {}, xhr: true

      assert_response_success
    end

    test "returns 404 trying to access campaign from wrong repo in different org" do
      other_org = create(:business_plus_organization, admin: @user)
      other_org.advanced_security_billable_entity&.mark_advanced_security_as_purchased_for_entity(actor: @user)

      other_repo = create(:private_repository, from_example: :simple, owner: other_org)
      other_repo.enable_advanced_security!(actor: @user)

      as @user
      get "/#{other_repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}", params: {}, xhr: true

      assert_response_not_found
    end

    test "returns 404 trying to access campaign from wrong repo in same org" do
      other_repo = create(:private_repository, from_example: :simple, owner: @org)
      other_repo.enable_advanced_security!(actor: @user)

      as @user
      get "/#{other_repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}", params: {}, xhr: true

      assert_response_not_found
    end
  end
end
