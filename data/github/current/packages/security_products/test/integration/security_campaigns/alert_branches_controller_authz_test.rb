# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityCampaignsAlertBranchesControllerAuthzTest < GitHub::IntegrationTestCase
  include WebAuthzTestHelpers
  include SecurityCampaigns::TestFixtures

  fixtures do
    create_repo_level_fixtures
  end

  setup do
    GitHub.flipper[:security_campaigns].enable

    if GitHub.enterprise?
      GitHub.stubs(:actions_enabled?).returns(true)
      GitHub.stubs(:code_scanning_enabled?).returns(true)
    else
      @org.advanced_security_billable_entity.mark_advanced_security_as_purchased_for_entity(actor: @owner)
    end

    @private_repo.enable_advanced_security!(actor: @owner)

    @create_params = {
      "name" => "branch-name",
      "alert_numbers" => [1, 3],
      "create_new_branch" => true,
    }
  end

  test "validate action authz" do
    assert_authz SecurityCampaigns::AlertBranchesController, repo_level_users do |expect|
      # create
      expect.post "/#{@private_repo.name_with_display_owner}/security/campaigns/#{@campaign.number}/branches", params: @create_params.merge({ name: "branch-#{SecureRandom.hex(16)}" }), xhr: true, as: @owner, returns: :ok
      expect.post "/#{@private_repo.name_with_display_owner}/security/campaigns/#{@campaign.number}/branches", params: @create_params.merge({ name: "branch-#{SecureRandom.hex(16)}" }), xhr: true, as: @security_manager, returns: :redirect
      expect.post "/#{@private_repo.name_with_display_owner}/security/campaigns/#{@campaign.number}/branches", params: @create_params.merge({ name: "branch-#{SecureRandom.hex(16)}" }), xhr: true, as: @repo_admin, returns: :ok
      expect.post "/#{@private_repo.name_with_display_owner}/security/campaigns/#{@campaign.number}/branches", params: @create_params.merge({ name: "branch-#{SecureRandom.hex(16)}" }), xhr: true, as: @repo_write, returns: :ok
      expect.post "/#{@private_repo.name_with_display_owner}/security/campaigns/#{@campaign.number}/branches", params: @create_params.merge({ name: "branch-#{SecureRandom.hex(16)}" }), xhr: true, as: @repo_read, returns: :not_found
      expect.post "/#{@private_repo.name_with_display_owner}/security/campaigns/#{@campaign.number}/branches", params: @create_params.merge({ name: "branch-#{SecureRandom.hex(16)}" }), xhr: true, as: @repo_code_scanning_write, returns: :redirect
      expect.post "/#{@private_repo.name_with_display_owner}/security/campaigns/#{@campaign.number}/branches", params: @create_params.merge({ name: "branch-#{SecureRandom.hex(16)}" }), xhr: true, as: @repo_code_scanning_read, returns: :not_found
      expect.post "/#{@private_repo.name_with_display_owner}/security/campaigns/#{@campaign.number}/branches", params: @create_params.merge({ name: "branch-#{SecureRandom.hex(16)}" }), xhr: true, as: @rando, returns: :not_found
      expect.post "/#{@private_repo.name_with_display_owner}/security/campaigns/#{@campaign.number}/branches", params: @create_params.merge({ name: "branch-#{SecureRandom.hex(16)}" }), xhr: true, as: @anon, returns: :not_found
    end
  end
end
