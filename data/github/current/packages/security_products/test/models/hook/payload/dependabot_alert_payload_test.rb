# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadDependabotAlertPayloadTest < GitHub::TestCase
  fixtures do
    @user_repository = create(:repository)
    @user = @user_repository.owner

    @organization_repository = create(:repository, :org_owned)
    @organization = @organization_repository.owner

    @enterprise_repository = create(:repository, :enterprise_linked_org_owned)
    @enterprise_organization = @enterprise_repository.owner
    @enterprise = @enterprise_organization.business

    @user_alert = create(:repository_vulnerability_alert, :active, repository: @user_repository)
    @organization_alert = create(:repository_vulnerability_alert, :active, repository: @organization_repository)
    @enterprise_alert = create(:repository_vulnerability_alert, :active, repository: @enterprise_repository)

    @inactive_alert = create(:repository_vulnerability_alert, :inactive)
  end

  def payload_hash(alert:, action: :created)
    Hook::Event::DependabotAlertEvent.new(action: action, alert_id: alert&.id).to_payload_hash
  end

  def user_alert_hash(**args)
    payload_hash(**T.unsafe({ alert: @user_alert, **args }))
  end

  def organization_alert_hash(**args)
    payload_hash(**T.unsafe({ alert: @organization_alert, **args }))
  end

  def enterprise_alert_hash(**args)
    payload_hash(**T.unsafe({ alert: @enterprise_alert, **args }))
  end

  test "returns null for a missing alert" do
    missing_alert_hash = payload_hash(alert: nil)

    assert_includes missing_alert_hash, :alert
    assert_nil missing_alert_hash[:alert]
  end

  test "returns null for an inactive alert" do
    inactive_alert_hash = payload_hash(alert: @inactive_alert)

    assert_includes inactive_alert_hash, :alert
    assert_nil inactive_alert_hash[:alert]
  end

  Hook::Event::DependabotAlertEvent::ACTIONS.each do |action|
    test "includes the #{action.inspect} action" do
      assert_equal action, user_alert_hash(action: action).dig(:action)
      assert_equal action, organization_alert_hash(action: action).dig(:action)
      assert_equal action, enterprise_alert_hash(action: action).dig(:action)
    end
  end

  # We test that the alert payload is present but don't fuss over the exact
  # contents of the payload. The serializer tests are a better place to assert
  # the full alert representation.
  test "includes the alert" do
    assert_equal @user_alert.permalink, user_alert_hash.dig(:alert, :html_url)
    assert_equal @organization_alert.permalink, organization_alert_hash.dig(:alert, :html_url)
    assert_equal @enterprise_alert.permalink, enterprise_alert_hash.dig(:alert, :html_url)
  end

  test "includes the repository" do
    assert_equal @user_repository.permalink, user_alert_hash.dig(:repository, :html_url)
    assert_equal @organization_repository.permalink, organization_alert_hash.dig(:repository, :html_url)
    assert_equal @enterprise_repository.permalink, enterprise_alert_hash.dig(:repository, :html_url)
  end

  test "excludes the organization for alerts on personal repositories" do
    refute_includes user_alert_hash, :organization
  end

  test "includes the organization for alerts on organizational repositories" do
    assert_equal @organization.login, organization_alert_hash.dig(:organization, :login)
    assert_equal @enterprise_organization.login, enterprise_alert_hash.dig(:organization, :login)
  end

  test "includes the global enterprise in Enterprise environments", enterprise_only: true do
    enterprise = GitHub.global_business
    assert enterprise, "Expected a global business instance in Enterprise"

    assert_equal enterprise.slug, user_alert_hash.dig(:enterprise, :slug)
    assert_equal enterprise.slug, organization_alert_hash.dig(:enterprise, :slug)
    assert_equal enterprise.slug, enterprise_alert_hash.dig(:enterprise, :slug)
  end

  test "excludes the enterprise for non-Enterprise-linked repositories in Dotcom", skip_enterprise: true do
    refute_includes user_alert_hash, :enterprise
    refute_includes organization_alert_hash, :enterprise
  end

  test "includes the enterprise for Enterprise-linked repositories in Dotcom", skip_enterprise: true do
    assert_equal @enterprise.slug, enterprise_alert_hash.dig(:enterprise, :slug)
  end

  test "includes the sender" do
    make_trusted_oauth_apps_owner
    refute_nil user_alert_hash.dig(:sender, :login)
    refute_nil organization_alert_hash.dig(:sender, :login)
    refute_nil enterprise_alert_hash.dig(:sender, :login)
  end
end
