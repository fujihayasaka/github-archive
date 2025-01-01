# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dependabot_github_app_helper"

module PullRequests
  module PageData
    class BannersDataPayloadTestWithoutSecurityUpdates < GitHub::TestCase
      include DependabotGithubAppHelper
      include GitHub::ComponentTestHelpers

      fixtures do
        make_trusted_oauth_apps_owner
        @user = create(:user)
        @user_without_write_access = create(:user)
        @repository = create(:repository, admin: @user, from_example: :review_comment_fork)
        create(:collaborator, collaborator: @user, repository: @repository)
        assert @repository.member?(@user)

        @open_user_pull = create(:pull_request,
          :with_mergeable_head,
          repository: @repository,
          base_repository: @repository,
          base_user: @user,
          base_ref: @repository.default_branch,
          head_repository: @repository,
          head_user: @user,
          head_ref_name: "topic2",
          user: @user,
        )

        @dependabot_app = create(:dependabot_integration)

        @open_dependabot_pull = create(:pull_request,
          :disable_disk_access,
          head_ref: "some-changes",
          repository: @repository,
          user: @dependabot_app.bot
        )
      end

      setup do
        GitHub.stubs(:dependabot_enabled?).returns(true) if GitHub.enterprise?
        reset_dependabot_github_app_memoization
        # Ensure we preload the Dependabot bot User before the test as we do not expect
        # the query to typically execute
        GitHub.dependabot_github_app_bot
        as @user
      end

      def expected_banners_payload(
        paused_dependabot_banner: false,
        hidden_character_banner: false
      )
        { banners: {
          dependabotAutomatedSecurityUpdates: { render: false },
          pausedDependabotUpdate: paused_dependabot_banner ? { render: true } : { render: false },
          hiddenCharacterWarning: hidden_character_banner ? { render: true } : { render: false }
          }
        }
      end

      context "author is not dependabot" do
        context "pull request is open" do
          context "service is paused" do
            test "does not indicate banners are needed" do
              Repository::DependabotServiceManager.new(@repository).pause

              banners_data_payload = BannersDataPayload.build(
                current_user: @user,
                pull_request: @open_user_pull,
                repository: @repository
              )

              assert_equal expected_banners_payload, banners_data_payload
            end
          end
        end
      end

      context "author is dependabot" do
        context "pull request is open" do
          context "service is paused" do
            test "returns showPausedDependabotUpdate true" do
              Repository::DependabotServiceManager.new(@repository).pause

              banners_data_payload = BannersDataPayload.build(
                current_user: @user,
                pull_request: @open_dependabot_pull,
                repository: @repository
              )

              assert_equal expected_banners_payload(paused_dependabot_banner: true), banners_data_payload
            end

            test "when checking write access a user without write permissions will not see the banner" do
              Repository::DependabotServiceManager.new(@repository).pause

              enable_feature_flag(:dependabot_paused_write_access_check)

              banners_data_payload = BannersDataPayload.build(
                current_user: @user_without_write_access,
                pull_request: @open_dependabot_pull,
                repository: @repository
              )

              assert_equal expected_banners_payload, banners_data_payload
            end

            test "without checking write access a user without write permissions will see the banner" do
              Repository::DependabotServiceManager.new(@repository).pause

              disable_feature_flag(:dependabot_paused_write_access_check)

              banners_data_payload = BannersDataPayload.build(
                current_user: @user_without_write_access,
                pull_request: @open_dependabot_pull,
                repository: @repository
              )

              assert_equal expected_banners_payload(paused_dependabot_banner: true), banners_data_payload
            end
          end
          context "service is not paused" do
            test "does not indicate banners are needed" do

              banners_data_payload = BannersDataPayload.build(
                current_user: @user,
                pull_request: @open_dependabot_pull,
                repository: @repository
              )

              assert_equal expected_banners_payload, banners_data_payload
            end
          end
        end
      end
      context "author is not relevant to the flag" do
        test "indicates hidden character banner is needed" do

          banners_data_payload = BannersDataPayload.build(
            current_user: @user,
            pull_request: @open_dependabot_pull,
            repository: @repository
          )

          assert_equal expected_banners_payload, banners_data_payload
        end
      end
    end
  end
end

module PullRequests
  module PageData
    class BannersDataPayloadTestWithSecurityUpdates < GitHub::TestCase
      include DependabotGithubAppHelper
      include GitHub::ComponentTestHelpers

      fixtures do
        make_trusted_oauth_apps_owner
        @user = create(:user)
        @user_without_write_access = create(:user)
        @repository = create(:repository, admin: @user, from_example: :review_comment_fork)
        create(:collaborator, collaborator: @user, repository: @repository)
        assert @repository.member?(@user)

        @open_user_pull = create(:pull_request,
          :with_mergeable_head,
          repository: @repository,
          base_repository: @repository,
          base_user: @user,
          base_ref: @repository.default_branch,
          head_repository: @repository,
          head_user: @user,
          head_ref_name: "topic2",
          user: @user,
        )

        @dependabot_app = create(:dependabot_integration)

        @open_dependabot_pull = create(:pull_request,
          :disable_disk_access,
          head_ref: "some-changes",
          repository: @repository,
          user: @dependabot_app.bot
        )

        @rva = create(:repository_vulnerability_alert, repository: @repository)

        dependency_update = create(
          :repository_dependency_update,
          :completed,
          pull_request: @open_dependabot_pull,
          repository: @repository,
          repository_vulnerability_alert: @rva,
          package_name: @rva.package_name
        )
      end

      def expected_banners_payload(
        automated_security_banner: false,
        paused_dependabot_banner: false,
        hidden_character_banner: false,
        multiple_alert_response: false
      )
        security_response = multiple_alert_response ? multiple_security_alerts_response : default_secutity_upate_response(automated_security_banner)

        { banners: {
          dependabotAutomatedSecurityUpdates: security_response,
          pausedDependabotUpdate: paused_dependabot_banner ? { render: true } : { render: false },
          hiddenCharacterWarning: hidden_character_banner ? { render: true } : { render: false }
          }
        }
      end

      def default_secutity_upate_response(automated_security_banner)
        if automated_security_banner
          {
            render: true,
            alertPresent: true,
            packageName: "rake",
            singleAlert: true,
            securityAlertPath: "/#{@repository.owner_display_login}/#{@repository.name}/security/dependabot",
            severity: "high",
            showOnboardingPopover: true,
            onboardingBannerProps: {
              dismissNoticePath: "/settings/dismiss-notice/automated_security_pull_requests",
              helpURL: GitHub.dependabot_security_updates_help_url,
              repoSettingsPath: "/#{@repository.owner_display_login}/#{@repository.name}/settings/security_analysis",
              showOptOut: false
            }
          }
        else
          { render: false }
        end
      end

      def multiple_security_alerts_response
        multple_alert_path = Rails.application.routes.url_helpers.repository_alerts_path(
          user_id: @repository.owner_display_login,
          repository: @repository.name,
          q: "package:#{@rva.package_name} manifest:#{@open_dependabot_pull.most_recent_vulnerability_dependency_update.manifest_path} has:patch"
        )
        {
            render: true,
            alertPresent: true,
            packageName: "rake",
            singleAlert: false,
            securityAlertPath: multple_alert_path,
            severity: "critical",
            showOnboardingPopover: true,
            onboardingBannerProps: {
              dismissNoticePath: "/settings/dismiss-notice/automated_security_pull_requests",
              helpURL: GitHub.dependabot_security_updates_help_url,
              repoSettingsPath: "/#{@repository.owner_display_login}/#{@repository.name}/settings/security_analysis",
              showOptOut: false
            }
          }
      end

      setup do
        GitHub.stubs(:dependabot_enabled?).returns(true) if GitHub.enterprise?
        reset_dependabot_github_app_memoization
        # Ensure we preload the Dependabot bot User before the test as we do not expect
        # the query to typically execute
        GitHub.dependabot_github_app_bot
        as @user
      end

      test "indicates that a security update banner is needed" do
        banners_data_payload = BannersDataPayload.build(
          current_user: @user,
          pull_request: @open_dependabot_pull,
          repository: @repository
        )

        assert_equal expected_banners_payload(automated_security_banner: true), banners_data_payload
      end

      test "indicates that a security update banner is not needed if the viewer should not see them" do
        banners_data_payload = BannersDataPayload.build(
          current_user: @user_without_write_access,
          pull_request: @open_dependabot_pull,
          repository: @repository
        )

        assert_equal expected_banners_payload, banners_data_payload
      end

      test "differentiates between a single or multiple alerts" do
        vvr = create(:vulnerable_version_range, affects: @rva.package_name)
        rva2 = create(
          :repository_vulnerability_alert,
          repository: @repository,
          severity: "critical",
          vulnerable_version_range: vvr,
          vulnerable_manifest_path: @rva.vulnerable_manifest_path
        )

        banners_data_payload = BannersDataPayload.build(
          current_user: @user,
          pull_request: @open_dependabot_pull,
          repository: @repository
        )

        expected_response = expected_banners_payload(automated_security_banner: true, multiple_alert_response: true)

        assert_equal expected_response, banners_data_payload
      end

      test "will not show the onboarding popover" do
        @user.dismiss_notice("automated_security_pull_requests")

        banners_data_payload = BannersDataPayload.build(
          current_user: @user,
          pull_request: @open_dependabot_pull,
          repository: @repository
        )

        assert_equal false, banners_data_payload.dig(:banners, :dependabotAutomatedSecurityUpdates, :showOnboardingPopover)
      end

      test "will show the opt out if the user meets the requirements" do

        banners_data_payload = BannersDataPayload.build(
          current_user: @repository.owner,
          pull_request: @open_dependabot_pull,
          repository: @repository
        )

        show_opt_out = banners_data_payload.dig(
          :banners,
          :dependabotAutomatedSecurityUpdates,
          :onboardingBannerProps,
          :showOptOut
        )

        assert_equal true, show_opt_out
      end

      test "indicates that all banners are needed" do
        Repository::DependabotServiceManager.new(@repository).pause

        disable_feature_flag(:dependabot_paused_write_access_check)

        enable_feature_flag(:collect_non_printing_chars_metrics)
        enable_feature_flag(:display_non_printing_chars_warning)

        @open_dependabot_pull.head_ref = "some-changes​o"

        banners_data_payload = BannersDataPayload.build(
          current_user: @user,
          pull_request: @open_dependabot_pull,
          repository: @repository
        )

        expected_response = expected_banners_payload(
          automated_security_banner: true,
          paused_dependabot_banner: true,
          hidden_character_banner: true
        )

        assert_equal expected_response, banners_data_payload
      end
    end
  end
end
