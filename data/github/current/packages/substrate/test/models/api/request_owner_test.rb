# typed: false
# frozen_string_literal: true

require "test_helper"

class Api::RequestOwnerTest < GitHub::TestCase
  def owner_id_for(**partial_args)
    empty_defaults = {
      user: nil,
      installation: nil,
      integration: nil,
      oauth_application: nil,
    }
    merged_args = empty_defaults.merge(partial_args)
    Api::RequestOwner.call(**merged_args)
  end

  fixtures do
    @requester = create(:user, login: "requester")
    @requester_org = create(:organization, name: "requester-org")
    @requester_org.add_member(@requester)
    @requester_org_oauth_application = create :oauth_application, user: @requester_org

    @third_party_allowed_app = create :oauth_application, user: create(:organization, name: "third-party-app-org")
    @other_requester_org = create(:organization, name: "other-requester-org", restrict_oauth_applications: true)
    @other_requester_org.add_member(@requester)
    @other_requester_org.approve_oauth_application(@third_party_allowed_app, approver: @requester)

    @ghec_requester_org = create(:organization, name: "ghec-requester-org", restrict_oauth_applications: true, plan: "business_plus")
    @ghec_requester_org.add_member(@requester)
    @ghec_requester_org.approve_oauth_application(@third_party_allowed_app, approver: @requester)

    @installed_on_org = create(:organization, name: "installed-on")

    @integration_owner = create(:organization, name: "integration-org")
    @integration = create(:integration, owner: @integration_owner)
    @installation = make_integration_installation(target: @installed_on_org, integration: @integration)

    @oauth_app_org = create(:organization, name: "oauth-app-org")
    @oauth_application = create :oauth_application, user: @oauth_app_org
  end

  # Setup `user` as though they'd been authenticated via API using `access`
  # @see User.with_oauth_hashed_token
  def with_oauth_access(access)
    user = access.user
    user.oauth_access = access
    user.set_scopes(access)
    user.oauth_application_id = access.application_id
    yield
  ensure
    user.oauth_access = nil
    user.scopes = nil
    user.oauth_application_id = nil
  end

  test "it does nothing for unauthenticated" do
    assert_nil owner_id_for(**{})
  end

  test "it does nothing for user without oauth_application" do
    assert_nil owner_id_for(user: @requester)
  end

  test "it does nothing for user with PAT" do
    with_oauth_access(make_personal_access_token(@requester)) do
      assert @requester.using_personal_access_token?
      assert_nil owner_id_for(user: @requester)
    end
  end

  test "it uses the oauth app owner when user.oauth_access is present AND the user is a member of that org" do
    access = @requester_org_oauth_application.grant(@requester)
    with_oauth_access(access) do
      assert_equal @requester_org_oauth_application, @requester.oauth_application
      assert_equal @requester_org, owner_id_for(user: @requester)
    end
  end

  test "doesn't use the OAuth app owner if the user is not a member of that org" do
    access = @oauth_application.grant(@requester)
    with_oauth_access(access) do
      assert_equal @oauth_application, @requester.oauth_application
      assert_nil owner_id_for(user: @requester)
    end
  end

  test "it returns GHEC org which explicitly allowed the app, if there is one" do
    access = @third_party_allowed_app.grant(@requester)
    with_oauth_access(access) do
      assert_equal @third_party_allowed_app, @requester.oauth_application
      assert_equal @ghec_requester_org, owner_id_for(user: @requester)
    end
  end

  test "it does nothing for user without app when oauth application is present" do
    assert_nil owner_id_for(user: @requester, oauth_application: @oauth_application)
  end

  test "it uses the installation target when an integration installation is present" do
    access = @integration.grant(@requester)
    with_oauth_access(access) do
      assert_equal @installed_on_org, owner_id_for(user: @requester, installation: @installation)
    end
  end

  test "it uses oauth app owner when only an oauth app is present" do
    assert_equal @oauth_app_org, owner_id_for(oauth_application: @oauth_application)
  end

  test "it uses github app owner when only a github app is present" do
    assert_equal @integration_owner, owner_id_for(integration: @integration)
  end

  test "it uses the github app owner for user-to-server requests" do
    access = make_oauth(@requester, ["user"], @integration)
    with_oauth_access(access) do
      assert_equal @integration_owner, owner_id_for(user: @requester, integration: @integration)
    end
  end

  test "it handles some nonsense situations" do
    # These don't make sense in real production situations, but they're tested here to keep an eye on behavior
    assert_equal @installed_on_org, owner_id_for(user: @requester, installation: @installation, oauth_application: @oauth_application)
    assert_equal @installed_on_org, owner_id_for(user: @requester, installation: @installation, integration: @integration)
    assert_nil owner_id_for(user: @requester, integration: @integration)
  end
end
