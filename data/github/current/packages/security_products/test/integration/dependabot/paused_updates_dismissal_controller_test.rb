# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"

class Dependabot::PausedUpdatesDismissalControllerTest < GitHub::IntegrationTestCase
  include DependabotAlertsEnterpriseEnablementHelper

  fixtures do
    @user = create(:user, login: "octocat")
    @repo = create(:repository, :vulnerability_alerts_enabled, owner: @user)
  end

  setup do
    stub_dependabot_alerts_enterprise_enablement if GitHub.enterprise?

    as @user
  end

  context "#dismiss_paused_banner" do
    test "dismiss endpoint hides banner from user" do
      Spokesd.enable_spokesd

      @repo.enable_vulnerability_updates(actor: @user)
      Repository.any_instance.stubs(:dependabot_updates_paused?).returns(true)

      # Validate the banner is rendering
      get "/#{@repo.name_with_display_owner}/security/dependabot"
      assert_select "[data-test-selector='dependabot-updates-paused-banner']", count: 1
      # Dismiss it
      post "/dependabot-updates-paused-banner/dismiss", xhr: true
      # Verify banner is no longer rendering
      get "/#{@repo.name_with_display_owner}/security/dependabot"
      refute_select "[data-test-selector='dependabot-updates-paused-banner']"
    end
  end

  test "paused banner endpoint returns 401 if not authenticated" do
    as @not_authenticated_user
    post "/dependabot-updates-paused-banner/dismiss", xhr: true
    assert_anon_response_unauthorized_or_not_found_in_mt
  end
end
