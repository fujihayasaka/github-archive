# typed: true
# frozen_string_literal: true

require "test_helper"

class Dependabot::DependabotAlertsOneClickUnsubscriptionsControllerTest < GitHub::IntegrationTestCase

  fixtures do
    @user = create(:user)
  end

  context "#create" do
    test "can unsubscribe from digest emails" do
      subscription = NewsletterSubscription.subscribe(@user, "vulnerability", "daily")
      token = NewsletterSubscription.get_unsubscribe_token(@user, "vulnerability")

      assert_changes -> { subscription.reload.active? }, from: true, to: false do
        post "/notifications/unsubscribe/dependabot-alerts/vulnerability-digest/#{token}",
          params: { "List-Unsubscribe" => "One-Click" }
      end

      assert_response :ok
    end

    test "can unsubscribe from new vulnerabilities emails" do
      token = Newsies::Authentication.token :unsubscribe_vulnerability_alerts, @user, 123

      assert_changes -> { GitHub.newsies.settings(@user).vulnerability_email? }, from: true, to: false do
        post "/notifications/unsubscribe/dependabot-alerts/new-vulnerabilities/#{token}",
          params: { "List-Unsubscribe" => "One-Click" }
      end

      assert_response :ok
    end

    test "returns unprocessable entity if the token is invalid" do
      post "/notifications/unsubscribe/dependabot-alerts/new-vulnerabilities/random-token",
        params: { "List-Unsubscribe" => "One-Click" }
      assert_response :forbidden

      post "/notifications/unsubscribe/dependabot-alerts/vulnerability-digest/random-token",
        params: { "List-Unsubscribe" => "One-Click" }
      assert_response :forbidden
    end

    test "returns unprocessable entity without the correct request body" do
      token = Newsies::Authentication.token :unsubscribe_vulnerability_alerts, @user, 123

      post "/notifications/unsubscribe/dependabot-alerts/new-vulnerabilities/#{token}"

      assert_response :bad_request
    end
  end
end
