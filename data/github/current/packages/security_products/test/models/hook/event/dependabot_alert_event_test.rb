# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventDependabotAlertEventTest < GitHub::TestCase
  include HookEventTestHelper
  include DependabotAlertsEnterpriseEnablementHelper

  fixtures do
    @repository = create(:repository)
    @hook = create(:hook, :web, installation_target: @repository, events: ["dependabot_alert"])

    @open_alert = create(:repository_vulnerability_alert, :open, repository: @repository)
    @dismissed_alert = create(:repository_vulnerability_alert, :dismissed, repository: @repository)
    @reopened_alert = create(:repository_vulnerability_alert, :reopened, repository: @repository)
    @fixed_alert = create(:repository_vulnerability_alert, :fixed, repository: @repository)
    @reintroduced_alert = create(:repository_vulnerability_alert, :reintroduced, repository: @repository)
    @auto_dismissed_alert = create(:repository_vulnerability_alert, :auto_dismissed, repository: @repository, ecosystem: "npm", dependency_scope: "development")

    @inactive_alert = create(:repository_vulnerability_alert, :inactive, repository: @repository)

    @missing_alert_id = RepositoryVulnerabilityAlert.maximum(:id) + 100
    @alert_with_missing_repository = create(:repository_vulnerability_alert, :active, repository_id: Repository.maximum(:id) + 100)
    @alert_with_missing_vulnerability = create(:repository_vulnerability_alert, :active, vulnerability_id: Vulnerability.maximum(:id) + 100)
    @alert_with_missing_vulnerable_version_range = create(:repository_vulnerability_alert, :active, vulnerable_version_range_id: VulnerableVersionRange.maximum(:id) + 100)

    @low_alert = create(:repository_vulnerability_alert, :active, severity: "low", repository: @repository)
    @moderate_alert = create(:repository_vulnerability_alert, :active, severity: "moderate", repository: @repository)
    @high_alert = create(:repository_vulnerability_alert, :active, severity: "high", repository: @repository)
    @critical_alert = create(:repository_vulnerability_alert, :active, severity: "critical", repository: @repository)
  end

  context "initialization" do
    test "action is required" do
      assert_event_required_attributes Hook::Event::DependabotAlertEvent, :action
    end

    test "alert_id is required" do
      assert_event_required_attributes Hook::Event::DependabotAlertEvent, :alert_id
    end
  end

  context ".visible_for?" do
    test "returns true on dotcom" do
      assert_equal true, SecurityProduct::VulnerabilityAlerts.enabled_for_instance?

      assert_equal true, Hook::Event::DependabotAlertEvent.visible_for?(nil, nil)
    end unless GitHub.enterprise?

    test "returns false if Dependabot Alerts are disabled on GHES" do
      assert_equal false, SecurityProduct::VulnerabilityAlerts.enabled_for_instance?

      assert_equal false, Hook::Event::DependabotAlertEvent.visible_for?(nil, nil)
    end if GitHub.enterprise?

    test "returns true if Dependabot Alerts are enabled on GHES" do
      stub_dependabot_alerts_enterprise_enablement
      assert_equal true, SecurityProduct::VulnerabilityAlerts.enabled_for_instance?

      assert_equal true, Hook::Event::DependabotAlertEvent.visible_for?(nil, nil)
    end if GitHub.enterprise?
  end

  context "#alert" do
    test "returns the specified alert" do
      event = Hook::Event::DependabotAlertEvent.new(
        action: :created,
        alert_id: @open_alert.id,
      )

      assert_equal @open_alert, event.alert
    end

    test "returns nil if the alert doesn't exist" do
      event = Hook::Event::DependabotAlertEvent.new(
        action: :created,
        alert_id: @missing_alert_id,
      )

      assert_nil event.alert
    end
  end

  context "#repository" do
    test "returns the alert's repository" do
      event = Hook::Event::DependabotAlertEvent.new(
        action: :created,
        alert_id: @open_alert.id,
      )

      assert_equal @open_alert.repository, event.repository
      assert_equal @open_alert.repository, event.target_repository
    end

    test "returns nil if the alert doesn't exist" do
      event = Hook::Event::DependabotAlertEvent.new(
        action: :created,
        alert_id: @missing_alert_id,
      )

      assert_nil event.repository
      assert_nil event.target_repository
    end

    test "returns nil if the alert's repository doesn't exist" do
      event = Hook::Event::DependabotAlertEvent.new(
        action: :created,
        alert_id: @alert_with_missing_repository.id,
      )

      assert_nil event.repository
      assert_nil event.target_repository
    end
  end

  context "#vulnerability" do
    test "returns the alert's vulnerability" do
      event = Hook::Event::DependabotAlertEvent.new(
        action: :created,
        alert_id: @open_alert.id,
      )

      assert_equal @open_alert.vulnerability, event.vulnerability
    end

    test "returns nil if the alert doesn't exist" do
      event = Hook::Event::DependabotAlertEvent.new(
        action: :created,
        alert_id: @missing_alert_id,
      )

      assert_nil event.vulnerability
    end

    test "returns nil if the alert's vulnerability doesn't exist" do
      event = Hook::Event::DependabotAlertEvent.new(
        action: :created,
        alert_id: @alert_with_missing_vulnerability.id,
      )

      assert_nil event.vulnerability
    end
  end

  context "#vulnerable_version_range" do
    test "returns the alert's vulnerable version range" do
      event = Hook::Event::DependabotAlertEvent.new(
        action: :created,
        alert_id: @open_alert.id,
      )

      assert_equal @open_alert.vulnerable_version_range, event.vulnerable_version_range
    end

    test "returns nil if the alert doesn't exist" do
      event = Hook::Event::DependabotAlertEvent.new(
        action: :created,
        alert_id: @missing_alert_id,
      )

      assert_nil event.vulnerable_version_range
    end

    test "returns nil if the alert's vulnerable version range doesn't exist" do
      event = Hook::Event::DependabotAlertEvent.new(
        action: :created,
        alert_id: @alert_with_missing_vulnerable_version_range.id,
      )

      assert_nil event.vulnerable_version_range
    end
  end

  context "#actor" do
    test "returns GitHub when the alert was created" do
      make_trusted_oauth_apps_owner
      event = Hook::Event::DependabotAlertEvent.new(
        action: :created,
        alert_id: @open_alert.id,
      )

      refute_nil event.actor
      assert_equal GitHub.trusted_oauth_apps_owner, event.actor
      assert_match %r{\Agithub}, event.actor.login
    end

    test "returns the alert's dismisser when the alert was dismissed" do
      event = Hook::Event::DependabotAlertEvent.new(
        action: :dismissed,
        alert_id: @dismissed_alert.id,
      )

      refute_nil event.actor
      assert_equal @dismissed_alert.last_state_change_actor, event.actor
    end

    test "returns the ghost user when the dismisser is missing" do
      @dismissed_alert.last_state_change_actor.delete # Poof!

      event = Hook::Event::DependabotAlertEvent.new(
        action: :dismissed,
        alert_id: @dismissed_alert.id,
      )

      refute_nil event.actor
      assert_equal User.ghost, event.actor
    end

    test "returns the alert's reopener when the alert was reopened" do
      event = Hook::Event::DependabotAlertEvent.new(
        action: :reopened,
        alert_id: @reopened_alert.id,
      )

      refute_nil event.actor
      assert_equal @reopened_alert.last_state_change_actor, event.actor
    end

    test "returns the ghost user when the reopener is missing" do
      @reopened_alert.last_state_change_actor.delete # Poof!

      event = Hook::Event::DependabotAlertEvent.new(
        action: :reopened,
        alert_id: @reopened_alert.id,
      )

      refute_nil event.actor
      assert_equal User.ghost, event.actor
    end

    test "returns GitHub when the alert was fixed" do
      make_trusted_oauth_apps_owner
      event = Hook::Event::DependabotAlertEvent.new(
        action: :fixed,
        alert_id: @fixed_alert.id,
      )

      refute_nil event.actor
      assert_equal GitHub.trusted_oauth_apps_owner, event.actor
      assert_match %r{\Agithub}, event.actor.login
    end

    test "returns GitHub when the alert was auto dismissed" do
      make_trusted_oauth_apps_owner
      event = Hook::Event::DependabotAlertEvent.new(
        action: :auto_dismissed,
        alert_id: @auto_dismissed_alert.id,
      )

      refute_nil event.actor
      assert_equal GitHub.trusted_oauth_apps_owner, event.actor
      assert_match %r{\Agithub}, event.actor.login
    end

    test "returns GitHub when the alert was reintroduced" do
      make_trusted_oauth_apps_owner
      event = Hook::Event::DependabotAlertEvent.new(
        action: :reintroduced,
        alert_id: @reintroduced_alert.id,
      )

      refute_nil event.actor
      assert_equal GitHub.trusted_oauth_apps_owner, event.actor
      assert_match %r{\Agithub}, event.actor.login
    end
  end

  context "#deliverable?" do
    test "returns true for a valid action on a data-complete alert" do
      event = Hook::Event::DependabotAlertEvent.new(
        action: :created,
        alert_id: @open_alert.id,
      )

      assert event.deliverable?
    end

    test "returns false for an invalid action" do
      event = Hook::Event::DependabotAlertEvent.new(
        action: :cremated, # Typo
        alert_id: @open_alert.id,
      )

      refute event.deliverable?
    end

    test "returns false for a missing alert" do
      event = Hook::Event::DependabotAlertEvent.new(
        action: :created,
        alert_id: @missing_alert_id,
      )

      refute event.deliverable?
    end

    test "returns false for an inactive alert" do
      event = Hook::Event::DependabotAlertEvent.new(
        action: :created,
        alert_id: @inactive_alert.id,
      )

      refute event.deliverable?
    end

    test "returns false if the alert's repository is missing" do
      event = Hook::Event::DependabotAlertEvent.new(
        action: :created,
        alert_id: @alert_with_missing_repository.id,
      )

      refute event.deliverable?
    end

    test "returns false if the alert's vulnerability is missing" do
      event = Hook::Event::DependabotAlertEvent.new(
        action: :created,
        alert_id: @alert_with_missing_vulnerability.id,
      )

      refute event.deliverable?
    end

    test "returns false if the alert's vulnerable version range is missing" do
      event = Hook::Event::DependabotAlertEvent.new(
        action: :created,
        alert_id: @alert_with_missing_vulnerable_version_range.id,
      )

      refute event.deliverable?
    end
  end
end
