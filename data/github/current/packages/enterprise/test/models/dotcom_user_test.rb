# typed: true
# frozen_string_literal: true

require "test_helper"

class DotcomUserTest < GitHub::TestCase
  fixtures do
    @user = create(:paid_user)
    @installation = create(:enterprise_installation)
  end

  test "for returns existing user or a new record" do
    user = DotcomUser.for(@user)
    assert user.new_record?
    user.save

    user = DotcomUser.for(@user)
    refute user.new_record?
  end

  context "#remove_user_contributions" do
    test "delegates a cleanup request using the token" do
      dotcom_user = create(:dotcom_user, user_id: @user.id, login: "testuser", token: "user-token")
      GitHub::Connect.expects(:remove_user_contributions).with("user-token").returns(true)
      assert dotcom_user.remove_user_contributions
    end

    test "runs before destroy and removes all user contributions" do
      dotcom_user = create(:dotcom_user, user_id: @user.id, login: "testuser", token: "user-token")
      dotcom_user.stubs(:revoke_oauth_token)
      EnterpriseContribution.destroy_all
      contrib = EnterpriseContribution.insert_or_update_contribution(@user, @installation, Date.today, 1)
      assert_equal [contrib.id], EnterpriseContribution.all.map(&:id)
      GitHub::Connect.expects(:remove_user_contributions).with("user-token").returns(true)
      dotcom_user.destroy
    end

    test "does nothing if token is empty (so instance disconnection can safely mass-destroy users)" do
      dotcom_user = create(:dotcom_user, user_id: @user.id, login: "testuser", token: nil)
      GitHub::Connect.expects(:remove_user_contributions).never
      assert_nothing_raised do
        dotcom_user.remove_user_contributions
      end
    end

    test "does nothing if dotcom doesn't recognize the token (e.g., because app was revoked)" do
      dotcom_user = create(:dotcom_user, user_id: @user.id, login: "testuser", token: "the_token")
      GitHub::Connect.stubs(:remove_user_contributions).raises(GitHub::Connect::ApiError.new("some non-success response removing the token"))
      assert_nothing_raised do
        dotcom_user.remove_user_contributions
      end
    end

    test "re-raises the error (so we can inform the user) if we can't talk to dotcom" do
      dotcom_user = create(:dotcom_user, user_id: @user.id, login: "testuser", token: "the_token")
      GitHub::Connect.stubs(:remove_user_contributions).raises(GitHub::Connect::ServiceUnavailableError.new("no interwebz"))
      assert_raises GitHub::Connect::ServiceUnavailableError do
        dotcom_user.remove_user_contributions
      end

      GitHub::Connect.stubs(:remove_user_contributions).raises(GitHub::Connect::TimeoutError.new("slow interwebz"))
      assert_raises GitHub::Connect::TimeoutError do
        dotcom_user.remove_user_contributions
      end
    end
  end

  context "#revoke_oauth_token" do
    test "retrieves oauth app info and uses it to revoke user oauth token" do
      dotcom_user = create(:dotcom_user, user_id: @user.id, login: "testuser", token: "user-token")
      GitHub::Connect::Authenticator.any_instance.expects(:request_oauth_application).returns("app info")
      GitHub::Connect::Authenticator.any_instance.expects(:revoke_oauth_token).with("user-token", "app info", nil)
      dotcom_user.revoke_oauth_token
    end

    test "runs before destroy" do
      dotcom_user = create(:dotcom_user, user_id: @user.id, login: "testuser", token: "user-token")
      dotcom_user.stubs(:remove_user_contributions)
      dotcom_user.expects(:revoke_oauth_token)
      dotcom_user.destroy
    end

    test "does nothing if token is empty (so instance disconnection can safely mass-destroy users)" do
      dotcom_user = create(:dotcom_user, user_id: @user.id, login: "testuser", token: nil)
      GitHub::Connect::Authenticator.any_instance.expects(:request_oauth_application).never
      GitHub::Connect::Authenticator.any_instance.expects(:revoke_oauth_token).never
      dotcom_user.revoke_oauth_token
    end
  end

  context "#github_profile_url" do
    test "builds a profile URL from the user's dotcom login" do
      dotcom_user = create(:dotcom_user, user_id: @user.id, login: "testuser")
      assert_equal "https://github.com/testuser", dotcom_user.github_profile_url
    end

    test "allows non-standard dotcom instances (review lab, local dotcom, etc.)" do
      dotcom_user = create(:dotcom_user, user_id: @user.id, login: "testuser")
      GitHub.stubs(:dotcom_host_protocol).returns("http")
      GitHub.stubs(:dotcom_host_name).returns("github.localhost")
      assert_equal "http://github.localhost/testuser", dotcom_user.github_profile_url
    end

    test "does not fail if dotcom login is empty (even though it should not be)" do
      dotcom_user = create(:dotcom_user, user_id: @user.id, login: nil)
      assert_equal "https://github.com", dotcom_user.github_profile_url
    end

    test "escapes logins (even though they should abide to login rules)" do
      dotcom_user = create(:dotcom_user, user_id: @user.id, login: "javascript:alert(1)")
      assert_equal "https://github.com/javascript%3Aalert%281%29", dotcom_user.github_profile_url
    end
  end

  context "#github_display_login" do
    test "returns the display login if present" do
      dotcom_user = create(:dotcom_user, user_id: @user.id, login: "testuser")
      assert_equal "testuser", dotcom_user.display_login
    end

    test "returns the display login with _ for :emus" do
      dotcom_user = create(:dotcom_user, user_id: @user.id, login: "testuser_fab")
      assert_includes dotcom_user.display_login, "_"
      assert_equal "testuser_fab", dotcom_user.display_login
    end
  end

  context "#github_display_login in Proxima" do
    test "returns the display login if present in proxima" do
      on_multi_tenant_enterprise
      GitHub.flipper.enable(:tenant_namespacing)
      emu = create :emu
      business = emu.enterprise_managed_business
      GitHub::CurrentTenant.set(business)

      dotcom_user = create(:dotcom_user, user_id: @user.id, login: emu.login)
      assert_equal emu.display_login, dotcom_user.display_login
      refute_includes dotcom_user.display_login, "_"
      refute_includes emu.display_login, "_"
      GitHub::CurrentTenant.remove
    end
  end
end
