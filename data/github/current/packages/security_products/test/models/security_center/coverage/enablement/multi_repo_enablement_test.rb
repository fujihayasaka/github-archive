# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Coverage
    module Enablement
      class MultiRepoEnablementTest < GitHub::TestCase
        include ::SecurityCenter::TestFixtures
        include CodeScanningHelper

        fixtures do
          create_org_level_fixtures

          @org_2 = create(:business_plus_organization, business: @biz, name: "test-org-2")
          @org_2_private_repo_1 = create(:private_repository, owner: @org_2, name: "#{@org_2}-private-repo").tap do |repo|
            create(:repository_security_center_config, repository: repo, owner: @org_2, name: repo.name, visibility: repo.visibility, last_push: repo.pushed_at)
            create(:repository_security_center_status, :dependabot_alerts, :enrolled, scanning_count: 1, repository: repo)
            create(:repository_security_center_status, :code_scanning, :enrolled, scanning_count: 2, repository: repo)
            create(:repository_security_center_status, :secret_scanning, :enrolled, scanning_count: 3, repository: repo)
          end
        end

        setup do
          GitHub.stubs(:code_scanning_enabled?).returns(true)
          GitHub.stubs(:dependabot_enabled?).returns(true)
          GitHub.stubs(:dependency_graph_enabled?).returns(true)

          SecurityProduct::VulnerabilityAlerts.stubs(:enabled_for_instance?).returns(true)

          Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)

          docs_base_url = GitHub.help_url(ghec_exclusive: true)
          @blocked_reason_dependency_graph = "#{MultiRepoEnablement::BLOCKED_BY_POLICY_MESSAGE} <a href=\"#{docs_base_url}/code-security/supply-chain-security/understanding-your-software-supply-chain/about-the-dependency-graph\">Learn more about this policy</a>."
          @blocked_reason_dependabot_alerts = "#{MultiRepoEnablement::BLOCKED_BY_POLICY_MESSAGE} <a href=\"#{docs_base_url}/code-security/dependabot/dependabot-alerts/about-dependabot-alerts\">Learn more about this policy</a>."
          @blocked_reason_dependabot_security_updates = "#{MultiRepoEnablement::BLOCKED_BY_POLICY_MESSAGE} <a href=\"#{docs_base_url}/code-security/dependabot/dependabot-security-updates/about-dependabot-security-updates\">Learn more about this policy</a>."
          @blocked_reason_ghas = "#{MultiRepoEnablement::BLOCKED_BY_POLICY_MESSAGE} <a href=\"#{docs_base_url}/get-started/learning-about-github/about-github-advanced-security\">Learn more about this policy</a>."
          @blocked_reason_secret_scanning = "#{MultiRepoEnablement::BLOCKED_BY_POLICY_MESSAGE} <a href=\"#{docs_base_url}/code-security/secret-scanning/about-secret-scanning\">Learn more about this policy</a>."
          @blocked_reason_push_protection = "#{MultiRepoEnablement::BLOCKED_BY_POLICY_MESSAGE} <a href=\"#{docs_base_url}/code-security/secret-scanning/protecting-pushes-with-secret-scanning\">Learn more about this policy</a>."

          @codeql_default_setup_description = [
            "Identify vulnerabilities and errors with ",
            ActionController::Base.helpers.link_to("CodeQL", "#{docs_base_url}/code-security/code-scanning/automatically-scanning-your-code-for-vulnerabilities-and-errors/about-code-scanning-with-codeql"),
            " for ",
            ActionController::Base.helpers.link_to("eligible", "#{docs_base_url}/code-security/code-scanning/automatically-scanning-your-code-for-vulnerabilities-and-errors/configuring-code-scanning-at-scale#eligible-repositories-for-codeql-default-setup"),
            " repositories. This will automatically find the best configuration for your selected repositories based on the chosen ",
            ActionController::Base.helpers.link_to("query suite", built_in_codeql_query_suites_docs_path(@org)),
            "."
          ].join

          @secret_scanning_alerts_description = [
            "Receive alerts on GitHub for detected secrets, keys, or other tokens. ",
            "GitHub will always send alerts to partners for detected secrets in public repositories. ",
            ActionController::Base.helpers.link_to(
              "Learn more about partner patterns",
              DocsUrlConfig.url_for("code-security/about-secret-scanning-alerts-for-partners", ghec: true)
            ),
            "."
          ].join

          @ghas_description_prefix = "GitHub Advanced Security features are billed per active committer."
          @ghas_description_prefix += " The features are free of charge in public repositories." unless GitHub.enterprise?

          # Setup GHAS license.
          @ghas_purchased_licenses = 20
          @ghas_consumed_licenses = 15
          @org.advanced_security_license.stubs(:seats).returns(@ghas_purchased_licenses)
          @org.advanced_security_license.stubs(:consumed_seats).returns(@ghas_consumed_licenses)

          @ghas_expected_increase = @org.advanced_security_license.remaining_seats - 1
          AdvancedSecurityLicense.any_instance
            .stubs(:seat_usage_increase_if_advanced_security_enabled_for_repos)
            .returns(@ghas_expected_increase)
        end

        context "#content_component_data" do
          context "dependency graph" do
            test "it returns dependency graph data" do
              data = MultiRepoEnablement.new(
                actor: @owner,
                org: @org,
                repo_ids_or_query_string: "is:private",
                user_session: @owner_user_session
              ).content_component_data

              description = "Understand your dependencies."
              description += " Dependency graph is always enabled for public repositories." unless GitHub.enterprise?

              expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                blocked_reason: GitHub.enterprise? ? @blocked_reason_dependency_graph : nil,
                can_disable: !GitHub.enterprise?,
                can_enable: !GitHub.enterprise?,
                description: description,
                is_available: true
              )

              assert_equal(expected_data, data&.dependency_graph)
            end

            context "when an enterprise policy restricts repo admins from modifying dependency graph", skip_enterprise: true do
              test "repo admins cannot modify dependency graph" do
                @biz.disallow_repo_admins_to_modify_dependabot_alerts_enablement(actor: @owner)

                [[@owner, @owner_user_session, true], [@security_manager, @security_manager_user_session, true], [@repo_admin, @repo_admin_user_session, false]].each do |actor, user_session, can_modify|
                  data = MultiRepoEnablement.new(
                    actor: actor,
                    org: @org,
                    repo_ids_or_query_string: "is:private",
                    user_session:
                  ).content_component_data

                  expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                    blocked_reason: can_modify ? nil : @blocked_reason_dependency_graph,
                    can_disable: can_modify,
                    can_enable: can_modify,
                    description: "Understand your dependencies. Dependency graph is always enabled for public repositories.",
                    is_available: true
                  )

                  assert_equal(expected_data, data&.dependency_graph)
                end
              end
            end

            context "GHES", enterprise_only: true do
              test "dependency graph cannot be modified" do
                @biz.disallow_repo_admins_to_modify_dependabot_alerts_enablement(actor: @owner)

                [[@owner, @owner_user_session], [@security_manager, @security_manager_user_session], [@repo_admin, @repo_admin_user_session]].each do |actor, user_session|
                  data = MultiRepoEnablement.new(
                    actor: actor,
                    org: @org,
                    repo_ids_or_query_string: "is:private",
                    user_session:
                  ).content_component_data

                  expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                    blocked_reason: @blocked_reason_dependency_graph,
                    can_disable: false,
                    can_enable: false,
                    description: "Understand your dependencies.",
                    is_available: true
                  )

                  assert_equal(expected_data, data&.dependency_graph)
                end
              end
            end

            context "when dependency graph is not enabled for the instance" do
              test "dependency graph is not available" do
                GitHub.stubs(:dependency_graph_enabled?).returns(false)

                data = MultiRepoEnablement.new(
                  actor: @owner,
                  org: @org,
                  repo_ids_or_query_string: "is:private",
                  user_session: @owner_user_session
                ).content_component_data

                description = "Understand your dependencies."
                description += " Dependency graph is always enabled for public repositories." unless GitHub.enterprise?

                expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                  blocked_reason: GitHub.enterprise? ? @blocked_reason_dependency_graph : nil,
                  can_disable: !GitHub.enterprise?,
                  can_enable: !GitHub.enterprise?,
                  description: description,
                  is_available: false
                )

                assert_equal(expected_data, data&.dependency_graph)
              end
            end
          end

          context "dependabot alerts" do
            test "it returns dependabot alerts data" do
              data = MultiRepoEnablement.new(
                actor: @owner,
                org: @org,
                repo_ids_or_query_string: "is:private",
                user_session: @owner_user_session
              ).content_component_data

              expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                can_disable: true,
                can_enable: true,
                description: "Receive alerts for vulnerabilities that affect your dependencies.",
                is_available: true
              )

              assert_equal(expected_data, data&.dependabot_alerts)
            end

            context "when an enterprise policy restricts repo admins from modifying dependabot alerts" do
              test "repo admins cannot edit dependabot alerts" do
                @biz.disallow_repo_admins_to_modify_dependabot_alerts_enablement(actor: @owner)

                [[@owner, @owner_user_session, true], [@security_manager, @security_manager_user_session, true], [@repo_admin, @repo_admin_user_session, false]].each do |actor, user_session, can_modify|
                  data = MultiRepoEnablement.new(
                    actor: actor,
                    org: @org,
                    repo_ids_or_query_string: "is:private",
                    user_session:
                  ).content_component_data

                  expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                    blocked_reason: can_modify ? nil : @blocked_reason_dependabot_alerts,
                    can_disable: can_modify,
                    can_enable: can_modify,
                    description: "Receive alerts for vulnerabilities that affect your dependencies.",
                    is_available: true
                  )

                  assert_equal(expected_data, data&.dependabot_alerts)
                end
              end
            end

            context "when dependabot alerts is not enabled for the instance" do
              test "dependabot alerts is not available" do
                SecurityProduct::VulnerabilityAlerts.stubs(:enabled_for_instance?).returns(false)

                data = MultiRepoEnablement.new(
                  actor: @owner,
                  org: @org,
                  repo_ids_or_query_string: "is:private",
                  user_session: @owner_user_session
                ).content_component_data

                expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                  can_disable: true,
                  can_enable: true,
                  description: "Receive alerts for vulnerabilities that affect your dependencies.",
                  is_available: false
                )

                assert_equal(expected_data, data&.dependabot_alerts)
              end
            end
          end

          context "dependabot security updates" do
            test "it returns dependabot security updates data" do
              data = MultiRepoEnablement.new(
                actor: @owner,
                org: @org,
                repo_ids_or_query_string: "is:private",
                user_session: @owner_user_session
              ).content_component_data

              expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                can_disable: true,
                can_enable: true,
                description: "Automatically open pull requests to resolve Dependabot alerts.",
                is_available: true
              )

              assert_equal(expected_data, data&.dependabot_security_updates)
            end

            context "when an enterprise policy restricts repo admins from modifying dependabot security updates" do
              test "repo admins cannot edit dependabot security updates" do
                @biz.disallow_repo_admins_to_modify_dependabot_alerts_enablement(actor: @owner)

                [[@owner, @owner_user_session, true], [@security_manager, @security_manager_user_session, true], [@repo_admin, @repo_admin_user_session, false]].each do |actor, user_session, can_modify|
                  data = MultiRepoEnablement.new(
                    actor: actor,
                    org: @org,
                    repo_ids_or_query_string: "is:private",
                    user_session:
                  ).content_component_data

                  expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                    blocked_reason: can_modify ? nil : @blocked_reason_dependabot_security_updates,
                    can_disable: can_modify,
                    can_enable: can_modify,
                    description: "Automatically open pull requests to resolve Dependabot alerts.",
                    is_available: true
                  )

                  assert_equal(expected_data, data&.dependabot_security_updates)
                end
              end
            end

            context "when dependabot security updates is not enabled for the instance" do
              test "dependabot security updates is not available" do
                GitHub.stubs(:dependabot_enabled?).returns(false)

                data = MultiRepoEnablement.new(
                  actor: @owner,
                  org: @org,
                  repo_ids_or_query_string: "is:private",
                  user_session: @owner_user_session
                ).content_component_data

                expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                  can_disable: true,
                  can_enable: true,
                  description: "Automatically open pull requests to resolve Dependabot alerts.",
                  is_available: false
                )

                assert_equal(expected_data, data&.dependabot_security_updates)
              end
            end
          end

          context "advanced security" do
            test "it returns advanced security data" do
              data = MultiRepoEnablement.new(
                actor: @owner,
                org: @org,
                repo_ids_or_query_string: "is:private",
                user_session: @owner_user_session
              ).content_component_data

              expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                can_disable: true,
                can_enable: true,
                description: "#{@ghas_description_prefix} Enabling will use #{@ghas_expected_increase} out of #{@org.advanced_security_license.remaining_seats} remaining GitHub Advanced Security licenses.",
                is_available: true
              )

              assert_equal(expected_data, data&.advanced_security)
            end

            context "when an enterprise policy restricts repo admins from modifying advanced security" do
              test "repo admins cannot edit advanced security" do
                @biz.disallow_repo_admins_to_modify_advanced_security_enablement(actor: @owner)

                [[@owner, @owner_user_session, true], [@security_manager, @security_manager_user_session, true], [@repo_admin, @repo_admin_user_session, false]].each do |actor, user_session, can_modify|
                  data = MultiRepoEnablement.new(
                    actor: actor,
                    org: @org,
                    repo_ids_or_query_string: "is:private",
                    user_session:
                  ).content_component_data

                  description = @ghas_description_prefix
                  if can_modify
                    description += " Enabling will use #{@ghas_expected_increase} out of #{@org.advanced_security_license.remaining_seats} remaining GitHub Advanced Security licenses."
                  end

                  expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                    blocked_reason: can_modify ? nil : @blocked_reason_ghas,
                    can_disable: can_modify,
                    can_enable: can_modify,
                    description: description,
                    is_available: true
                  )

                  assert_equal(expected_data, data&.advanced_security)
                end
              end
            end

            context "when enabling advanced security would exceed the number of available licenses" do
              test "advanced security cannot be enabled" do
                GitHub.flipper[:advanced_security_circuit_breaker].disable

                ghas_expected_increase = @org.advanced_security_license.remaining_seats + 1
                AdvancedSecurityLicense.any_instance
                  .stubs(:seat_usage_increase_if_advanced_security_enabled_for_repos)
                  .returns(ghas_expected_increase)

                data = MultiRepoEnablement.new(
                  actor: @owner,
                  org: @org,
                  repo_ids_or_query_string: "is:private",
                  user_session: @owner_user_session
                ).content_component_data

                expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                  blocked_reason: nil,
                  can_disable: true,
                  can_enable: false,
                  description: "#{@ghas_description_prefix} You do not have enough licenses to enable GitHub Advanced Security.",
                  is_available: true
                )

                assert_equal(expected_data, data&.advanced_security)
              end
            end

            context "when an enterprise policy restricts organizations from enabling advanced security" do
              test "advanced security cannot be enabled" do
                @org.business.disallow_members_to_enable_advanced_security(actor: @owner)

                [[@owner, @owner_user_session], [@security_manager, @security_manager_user_session], [@repo_admin, @repo_admin_user_session]].each do |actor, user_session|
                  data = MultiRepoEnablement.new(
                    actor: actor,
                    org: @org,
                    repo_ids_or_query_string: "is:private",
                    user_session:
                  ).content_component_data

                  expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                    can_disable: true,
                    can_enable: false,
                    description: "#{@ghas_description_prefix} An enterprise-level policy has restricted enablement.",
                    is_available: true
                  )

                  assert_equal(expected_data, data&.advanced_security)
                end
              end
            end

            context "when advanced security is blocked by an in progress setting" do
              test "advanced security is blocked" do
                BlockedSettings.any_instance.expects(:advanced_security?).at_least_once.returns(true)

                data = MultiRepoEnablement.new(
                  actor: @owner,
                  org: @org,
                  repo_ids_or_query_string: "is:private",
                  user_session: @owner_user_session
                ).content_component_data

                expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                  blocked_reason: MultiRepoEnablement::BLOCKED_SETTINGS_MESSAGE,
                  can_disable: false,
                  can_enable: false,
                  description: @ghas_description_prefix,
                  is_available: true
                )

                assert_equal(expected_data, data&.advanced_security)
              end
            end

            context "when advanced security is not purchased" do
              test "advanced security is not available" do
                Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)

                data = MultiRepoEnablement.new(
                  actor: @owner,
                  org: @org,
                  repo_ids_or_query_string: "is:private",
                  user_session: @owner_user_session
                ).content_component_data

                expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                  can_disable: true,
                  can_enable: true,
                  description: "#{@ghas_description_prefix} Enabling will use #{@ghas_expected_increase} out of #{@org.advanced_security_license.remaining_seats} remaining GitHub Advanced Security licenses.",
                  is_available: false
                )

                assert_equal(expected_data, data&.advanced_security)
              end
            end

            context "when turboghas is not available" do
              test "advanced security is blocked" do
                AdvancedSecurityLicense.any_instance.unstub(:seat_usage_increase_if_advanced_security_enabled_for_repos)
                AdvancedSecurityLicense.stubs(:summary).raises(AdvancedSecurityLicense::TurboghasError.new("boom"))

                data = MultiRepoEnablement.new(
                  actor: @owner,
                  org: @org,
                  repo_ids_or_query_string: "is:private",
                  user_session: @owner_user_session
                ).content_component_data

                expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                  blocked_reason: "Unable to determine license usage. Please try again later.",
                  can_disable: false,
                  can_enable: false,
                  description: @ghas_description_prefix,
                  is_available: true
                )

                assert_equal(expected_data, data&.advanced_security)
              end
            end
          end

          context "CodeQL Default Setup" do
            test "it returns CodeQL Default Setup data" do
              data = MultiRepoEnablement.new(
                actor: @owner,
                org: @org,
                repo_ids_or_query_string: "is:private",
                user_session: @owner_user_session
              ).content_component_data

              expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                can_disable: true,
                can_enable: true,
                description: @codeql_default_setup_description,
                is_available: true
              )

              assert_equal(expected_data, data&.codeql_default_setup)
            end

            context "when code scanning is not enabled for the instance" do
              test "code scanning is not available" do
                ::SecurityCenter::SecurityFeatures.stubs(:code_scanning_enabled_for_instance?).returns(false)

                data = MultiRepoEnablement.new(
                  actor: @owner,
                  org: @org,
                  repo_ids_or_query_string: "is:private",
                  user_session: @owner_user_session
                ).content_component_data

                expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                  can_disable: true,
                  can_enable: true,
                  description: @codeql_default_setup_description,
                  is_available: false
                )

                assert_equal(expected_data, data&.codeql_default_setup)
              end
            end

            context "when code scanning is blocked by an in progress setting" do
              test "code scanning is blocked" do
                BlockedSettings.any_instance.expects(:code_scanning?).at_least_once.returns(true)

                data = MultiRepoEnablement.new(
                  actor: @owner,
                  org: @org,
                  repo_ids_or_query_string: "is:private",
                  user_session: @owner_user_session
                ).content_component_data

                expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                  blocked_reason: MultiRepoEnablement::BLOCKED_SETTINGS_MESSAGE,
                  can_disable: false,
                  can_enable: false,
                  description: @codeql_default_setup_description,
                  is_available: true
                )

                assert_equal(expected_data, data&.codeql_default_setup)
              end
            end
          end

          context "secret scanning" do
            test "it returns secret scanning data" do
              data = MultiRepoEnablement.new(
                actor: @owner,
                org: @org,
                repo_ids_or_query_string: "is:private",
                user_session: @owner_user_session
              ).content_component_data

              expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                description: @secret_scanning_alerts_description,
              )

              assert_equal(expected_data, data&.secret_scanning_alerts)
            end

            context "when secret scanning is not enabled for the instance" do
              test "secret scanning is not available" do
                SecretScanning::Features::Owner::TokenScanning.any_instance.stubs(:feature_available?).returns(false)

                data = MultiRepoEnablement.new(
                  actor: @owner,
                  org: @org,
                  repo_ids_or_query_string: "is:private",
                  user_session: @owner_user_session
                ).content_component_data

                expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                  blocked_reason: nil,
                  can_disable: true,
                  can_enable: true,
                  description: @secret_scanning_alerts_description,
                  is_available: false
                )

                assert_equal(expected_data, data&.secret_scanning_alerts)
              end
            end

            context "when an enterprise policy restricts repo admins from modifying secret scanning" do
              test "repo admins cannot modify secret scanning" do
                @biz.disallow_repo_admins_to_modify_secret_scanning_settings(actor: @owner)

                [[@owner, @owner_user_session, true], [@security_manager, @security_manager_user_session, true], [@repo_admin, @repo_admin_user_session, false]].each do |actor, user_session, can_modify|
                  data = MultiRepoEnablement.new(
                    actor: actor,
                    org: @org,
                    repo_ids_or_query_string: "is:private",
                    user_session:
                  ).content_component_data

                  expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                    blocked_reason: can_modify ? nil : @blocked_reason_secret_scanning,
                    can_disable: can_modify,
                    can_enable: can_modify,
                    description: @secret_scanning_alerts_description,
                    is_available: true
                  )

                  assert_equal(expected_data, data&.secret_scanning_alerts)
                end
              end
            end

            context "when secret scanning is blocked by an in progress setting" do
              test "secret scanning is blocked" do
                BlockedSettings.any_instance.expects(:secret_scanning?).at_least_once.returns(true)

                data = MultiRepoEnablement.new(
                  actor: @owner,
                  org: @org,
                  repo_ids_or_query_string: "is:private",
                  user_session: @owner_user_session
                ).content_component_data

                expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                  blocked_reason: MultiRepoEnablement::BLOCKED_SETTINGS_MESSAGE,
                  can_disable: false,
                  can_enable: false,
                  description: @secret_scanning_alerts_description,
                  is_available: true
                )

                assert_equal(expected_data, data&.secret_scanning_alerts)
              end
            end
          end

          context "push protection" do
            test "it returns push protection data" do
              data = MultiRepoEnablement.new(
                actor: @owner,
                org: @org,
                repo_ids_or_query_string: "is:private",
                user_session: @owner_user_session
              ).content_component_data

              expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                description: "Block commits that contain secrets.",
              )

              assert_equal(expected_data, data&.secret_scanning_push_protection)
            end

            context "when secret scanning is not enabled for the instance" do
              test "push protection is not available" do
                SecretScanning::Features::Owner::PushProtection.any_instance.stubs(:feature_available?).returns(false)

                data = MultiRepoEnablement.new(
                  actor: @owner,
                  org: @org,
                  repo_ids_or_query_string: "is:private",
                  user_session: @owner_user_session
                ).content_component_data

                expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                  can_disable: true,
                  can_enable: true,
                  description: "Block commits that contain secrets.",
                  is_available: false
                )

                assert_equal(expected_data, data&.secret_scanning_push_protection)
              end
            end

            context "when an enterprise policy restricts repo admins from modifying secret scanning" do
              test "repo admins cannot modify push protection" do
                @biz.disallow_repo_admins_to_modify_secret_scanning_settings(actor: @owner)

                [[@owner, @owner_user_session, true], [@security_manager, @security_manager_user_session, true], [@repo_admin, @repo_admin_user_session, false]].each do |actor, user_session, can_modify|
                  data = MultiRepoEnablement.new(
                    actor: actor,
                    org: @org,
                    repo_ids_or_query_string: "is:private",
                    user_session:
                  ).content_component_data

                  expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                    blocked_reason: can_modify ? nil : @blocked_reason_push_protection,
                    can_disable: can_modify,
                    can_enable: can_modify,
                    description: "Block commits that contain secrets.",
                    is_available: true
                  )

                  assert_equal(expected_data, data&.secret_scanning_push_protection)
                end
              end
            end

            context "when secret scanning is blocked by an in progress setting" do
              test "push protection is blocked" do
                BlockedSettings.any_instance.expects(:push_protection?).at_least_once.returns(true)

                data = MultiRepoEnablement.new(
                  actor: @owner,
                  org: @org,
                  repo_ids_or_query_string: "is:private",
                  user_session: @owner_user_session
                ).content_component_data

                expected_data = MultiRepoEnablementContentComponent::FeatureData.new(
                  blocked_reason: MultiRepoEnablement::BLOCKED_SETTINGS_MESSAGE,
                  can_disable: false,
                  can_enable: false,
                  description: "Block commits that contain secrets.",
                  is_available: true
                )

                assert_equal(expected_data, data&.secret_scanning_push_protection)
              end
            end
          end
        end

        context "#repository_security_center_config_scope" do
          context "when a Coverage query is provided" do
            test "it returns an ActiveRecord::Relation matching the query" do
              instance = SecurityCenter::Coverage::Enablement::MultiRepoEnablement.new(
                actor: @owner,
                org: @org,
                repo_ids_or_query_string: "is:private",
                user_session: @owner_user_session
              )
              res = instance.repository_security_center_config_scope
              expected_repo_configs = RepositorySecurityCenterConfig.where(repository_id: [@private_repo.id, @another_repo.id])

              assert_kind_of(ActiveRecord::Relation, res)
              assert_same_elements(expected_repo_configs, res)
            end
          end

          context "when an array of repo IDs is provided" do
            test "it returns an ActiveRecord::Relation matching the repo IDs" do
              repo_ids = [@private_repo.id, @another_repo.id]
              instance = SecurityCenter::Coverage::Enablement::MultiRepoEnablement.new(
                actor: @owner,
                org: @org,
                repo_ids_or_query_string: repo_ids,
                user_session: @owner_user_session
              )
              res = instance.repository_security_center_config_scope
              expected_repo_configs = RepositorySecurityCenterConfig.where(repository_id: repo_ids)

              assert_kind_of(ActiveRecord::Relation, instance.repository_security_center_config_scope)
              assert_same_elements(expected_repo_configs, res)
            end
          end
        end
      end
    end
  end
end
