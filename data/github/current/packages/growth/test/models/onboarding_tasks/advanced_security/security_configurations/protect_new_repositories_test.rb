# typed: true
# frozen_string_literal: true

require "test_helper"

class OnboardingTasks::AdvancedSecurity::SecurityConfigurations::ProtectNewRepositoriesTest < GitHub::TestCase
  include HydroTestHelpers
  include UrlHelper

  fixtures do
    @owner = create(:user)
    @org = create(:organization, login: "my-hero", admin: @owner)
    @ghr_config = SecurityConfiguration.github_recommended_configuration
  end

  context "#task_link" do
    test "returns the correct path" do
      task = OnboardingTasks::AdvancedSecurity::SecurityConfigurations::ProtectNewRepositories.new(
        taskable: @org,
        user: @owner
      )

      assert_equal "/organizations/my-hero/settings/security_products/configurations/view/#{@ghr_config.id}?tip=protect_new_repositories", task.task_link
    end
  end

  context "#verify_task" do
    test "returns true if there is a security configuration default applied to the org public repos" do
      task = OnboardingTasks::AdvancedSecurity::SecurityConfigurations::ProtectNewRepositories.new(
        taskable: @org,
        user: @owner
      )

      SecurityConfigurationDefault.create(
        target: @org,
        default_for_new_public_repos: true,
        security_configuration_id: SecurityConfiguration.github_recommended_configuration&.id
      )

      assert_predicate task, :verify_task
    end

    test "returns true if there is a security configuration default applied to the org private repos" do
      task = OnboardingTasks::AdvancedSecurity::SecurityConfigurations::ProtectNewRepositories.new(
        taskable: @org,
        user: @owner
      )

      SecurityConfigurationDefault.create(
        target: @org,
        default_for_new_private_repos: true,
        security_configuration_id: T.must(SecurityConfiguration.github_recommended_configuration).id
      )

      assert_predicate task, :verify_task
    end

    test "returns false if there is no security configuration default applied to the org" do
      task = OnboardingTasks::AdvancedSecurity::SecurityConfigurations::ProtectNewRepositories.new(
        taskable: @org,
        user: @owner
      )

      refute_predicate task, :verify_task
    end
  end

end if GitHub.billing_enabled?
