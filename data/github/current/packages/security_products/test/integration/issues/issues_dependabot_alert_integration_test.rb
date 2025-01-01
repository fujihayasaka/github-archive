# typed: true
# frozen_string_literal: true

require "test_helper"

class IssuesDependabotAlertIntegrationTest < GitHub::IntegrationTestCase
  include ResiliencyHelpers
  include DependabotAlertsEnterpriseEnablementHelper

  setup do
    stub_dependabot_alerts_enterprise_enablement if GitHub.enterprise?
    GitHub.flipper[:issues_react_v2].disable
  end

  fixtures do
    @repo = create(:repository, :vulnerability_alerts_enabled)
    @alert = create(:repository_vulnerability_alert, { severity: "high", repository: @repo })

    path = "/#{@repo.name_with_display_owner}/security/dependabot/#{@alert.number}"
    @issue = create(:issue, repository: @repo, body: "# This is my issue\n\nSee #{GitHub.url}#{path}")
  end

  test "when authorized for alerts, a url to an alert is replaced with a pretty link" do
    as @repo.owner

    get "/#{@repo.name_with_display_owner}/issues/#{@issue.number}"
    assert_response :success
    assert_rich_alert_mention(@alert)
  end

  test "when unauthorized for alerts, an url to an alert is not changed" do
    as @issue.user

    get "/#{@repo.name_with_display_owner}/issues/#{@issue.number}"
    assert_response :success
    assert_plain_alert_mention(@alert)
  end

  context "when the Notify cluster is down", skip_enterprise: true do # Enterprise doesn't have seperate DB clusters
    test "gracefully fails" do
      as @repo.owner

      with_non_required_clusters_raising do
        get "/#{@repo.name_with_display_owner}/issues/#{@issue.number}"
        assert_response :success
        assert_plain_alert_mention(@alert)
      end
    end

    test "gracefully fails when cached" do
      as @repo.owner

      with_cache_enabled do
        # Prime the cache
        get "/#{@repo.name_with_display_owner}/issues/#{@issue.number}"
        assert_response :success
        assert_rich_alert_mention(@alert)

        with_non_required_clusters_raising do
          # Test without the notify cluster
          get "/#{@repo.name_with_display_owner}/issues/#{@issue.number}"
          assert_response :success
          assert_plain_alert_mention(@alert)
        end

        # Test with the notify cluster restored
        get "/#{@repo.name_with_display_owner}/issues/#{@issue.number}"
        assert_response :success
        assert_rich_alert_mention(@alert)
      end
    end
  end

  private

  def assert_rich_alert_mention(alert)
    assert_select ".d-block.markdown-body a", count: 1 do |element|
      assert_equal "/#{@repo.name_with_display_owner}/security/dependabot/#{alert.number}", element.at("a")["href"]
      assert_equal alert.title[0..96], element.at("a").text[0..96] # rendered alert title is truncated
    end
  end

  def assert_plain_alert_mention(alert)
    assert_select ".d-block.markdown-body a", count: 1 do |element|
      assert_equal "#{GitHub.url}/#{@repo.name_with_display_owner}/security/dependabot/#{alert.number}", element.at("a").text
      assert_equal "#{GitHub.url}/#{@repo.name_with_display_owner}/security/dependabot/#{alert.number}", element.at("a")["href"]
    end
  end
end
