# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityCampaignsRepositoryCountsControllerAuthzTest < GitHub::IntegrationTestCase
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

    GitHub::Turboscan.stubs(:alerts_by_repo).returns(Twirp::ClientResp.new(
      data: Turboscan::Proto::AlertsByRepoResponse.new({
        results: [],
      })
    ))

    @params = {
      "items" => {
        "item-0" => { "number" => @campaign.number },
      },
    }
  end

  test "validate action authz" do
    not_found_anon = TestEnv.test_with_all_emus? ? :redirect : :not_found

    assert_authz SecurityCampaigns::RepositoryCountsController, repo_level_users do |expect|
      # index
      expect.get "/#{@private_repo.name_with_display_owner}/security/campaigns/counts", params: @params, xhr: true, as: @owner, returns: :ok
      expect.get "/#{@private_repo.name_with_display_owner}/security/campaigns/counts", params: @params, xhr: true, as: @security_manager, returns: :ok
      expect.get "/#{@private_repo.name_with_display_owner}/security/campaigns/counts", params: @params, xhr: true, as: @repo_admin, returns: :ok
      expect.get "/#{@private_repo.name_with_display_owner}/security/campaigns/counts", params: @params, xhr: true, as: @repo_write, returns: :ok
      expect.get "/#{@private_repo.name_with_display_owner}/security/campaigns/counts", params: @params, xhr: true, as: @repo_read, returns: :not_found
      expect.get "/#{@private_repo.name_with_display_owner}/security/campaigns/counts", params: @params, xhr: true, as: @repo_code_scanning_write, returns: :ok
      expect.get "/#{@private_repo.name_with_display_owner}/security/campaigns/counts", params: @params, xhr: true, as: @repo_code_scanning_read, returns: :not_found
      expect.get "/#{@private_repo.name_with_display_owner}/security/campaigns/counts", params: @params, xhr: true, as: @rando, returns: :not_found
      expect.get "/#{@private_repo.name_with_display_owner}/security/campaigns/counts", params: @params, xhr: true, as: @anon, returns: not_found_anon
    end
  end
end
