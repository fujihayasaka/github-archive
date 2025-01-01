# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotUserTest < GitHub::TestCase
  context "#copilot_for_business_enabled?" do
    test "defaults to false" do
      user = create(:user)
      refute Copilot::User.new(user).copilot_for_business_enabled?
    end

    test "returns true if the user has a CFB seat" do
      user = create(:user)
      business = create(:business)
      organization = create(:organization, business: business)
      organization.add_member user
      create(:copilot_seat, assigned_user: user, organization: organization)
      assert Copilot::User.new(user).copilot_for_business_enabled?
    end
  end

  context "#codespaces_demo_usage_allowed?" do
    test "returns true for codespaces created from the demo repository" do
      repository = create(:repository)
      GitHub.flipper[:codespaces_copilot_demo_repository].enable(repository)

      user = create(:user)
      codespace = create(:codespace, owner: user, repository:)

      assert Copilot::User.new(user).codespaces_demo_usage_allowed?(codespace)
    end

    test "returns false for codespaces created from other repositories" do
      repository = create(:repository)
      GitHub.flipper[:codespaces_copilot_demo_repository].disable(repository)

      user = create(:user)
      codespace = create(:codespace, owner: user, repository:)

      refute Copilot::User.new(user).codespaces_demo_usage_allowed?(codespace)
    end
  end

  context "#codespaces_demo_request_allowed?" do
    test "returns false if there's no oauth_access" do
      user = create(:user)
      user.oauth_access = nil

      refute Copilot::User.new(user).codespaces_demo_request_allowed?
    end

    test "returns false for an OAuth token" do
      user = create(:user)
      user.oauth_access = make_oauth(user)

      refute Copilot::User.new(user).codespaces_demo_request_allowed?
    end

    test "returns false for a PAT" do
      user = create(:user)
      user.oauth_access = make_pat(user, scopes: [:repo])

      refute Copilot::User.new(user).codespaces_demo_request_allowed?
    end

    test "returns false for some other integration's installation" do
      user = create(:user)
      repo = create(:repository, owner: user)

      installation = make_integration_installation(repository: repo)
      grant = installation.integration.grant(user)

      new_access, error_response = installation.integration.grant_scoped_access_from(grant, user)
      assert_nil error_response

      user.oauth_access = new_access

      refute Copilot::User.new(user).codespaces_demo_request_allowed?
    end
  end
end if GitHub.copilot_enabled?
