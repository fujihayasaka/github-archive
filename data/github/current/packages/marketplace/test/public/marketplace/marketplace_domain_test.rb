# typed: true
# frozen_string_literal: true

require "test_helper"

class Marketplace::HasThirdPartyCiTest < GitHub::TestCase
  fixtures do
    make_trusted_oauth_apps_owner
    @repo = create :repository, from_example: :simple
  end

  setup do
    @domain = Marketplace::Domain.new
  end

  test "does not identify repositories by default" do
    refute @domain.repository_settings.has_third_party_ci?(@repo)
  end

  test "identifies repositories with statuses" do
    create(:status, repository: @repo)
    assert @domain.repository_settings.has_third_party_ci?(@repo)
  end

  test "identifies repositories with third party checks app" do
    integration = create :integration, default_permissions: { "checks": :write }
    make_integration_installation(target: @repo.owner, repository: @repo, integration: integration)
    assert @domain.repository_settings.has_third_party_ci?(@repo)
  end

  test "does not identify repositories with the Actions app", skip_enterprise: true do
    actions_app = create :launch_integration
    make_integration_installation(target: @repo.owner, repository: @repo, integration: actions_app)
    refute @domain.repository_settings.has_third_party_ci?(@repo)
  end

  test "does not identify repositories with first party, non user-installable apps with the checks permission" do
    integration = create_privileged_app_with_capabilities(
      capabilities: { user_installable: false },
      options: { default_permissions: { "checks": :write } }
    )
    make_integration_installation(target: @repo.owner, repository: @repo, integration: integration)
    refute @domain.repository_settings.has_third_party_ci?(@repo)
  end
end

class Marketplace::HasCiTest < GitHub::TestCase
  fixtures do
    make_trusted_oauth_apps_owner
    @actions_app = create :launch_integration
    @repo = create :repository, from_example: :simple
  end

  setup do
    @domain = Marketplace::Domain.new
  end

  test "does not identify repositories by default" do
    refute @domain.repository_settings.has_ci?(@repo)
  end

  test "identifies repositories with statuses" do
    create(:status, repository: @repo)
    assert @domain.repository_settings.has_ci?(@repo)
  end

  test "identifies repositories with third party checks app" do
    integration = create :integration, default_permissions: { "checks": :write }
    make_integration_installation(target: @repo.owner, repository: @repo, integration: integration)
    assert @domain.repository_settings.has_ci?(@repo)
  end

  test "identifies repositories with the Actions app", skip_enterprise: true do
    make_integration_installation(target: @repo.owner, repository: @repo, integration: @actions_app)
    assert @domain.repository_settings.has_ci?(@repo)
  end

  test "does not identify repositories with first party, non user-installable internal apps that have checks permission" do
    integration = create_privileged_app_with_capabilities(
      capabilities: { user_installable: false },
      options: { default_permissions: { "checks": :write } }
    )
    make_integration_installation(target: @repo.owner, repository: @repo, integration: integration)
    refute @domain.repository_settings.has_ci?(@repo)
  end
end
