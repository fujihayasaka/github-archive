# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Coverage
    module Enablement
      class MultiRepoEnablement
        extend T::Sig
        include GitHub::Memoizer
        include ActionView::Helpers::OutputSafetyHelper
        include CodeScanningHelper

        BLOCKED_SETTINGS_MESSAGE = "An org-level configuration update is in progress. Please try again later."
        BLOCKED_BY_POLICY_MESSAGE = "Modifying this feature has been blocked by an enterprise policy."

        sig { returns(User) }; attr_reader :actor
        sig { returns(Organization) }; attr_reader :org
        sig { returns(T.any(T::Array[Integer], String)) }; attr_reader :repo_ids_or_query_string
        sig { returns(UserSession) }; attr_reader :user_session

        sig do
          params(
            actor: User,
            org: Organization,
            repo_ids_or_query_string: T.any(T::Array[Integer], String),
            user_session: UserSession
          ).void
        end
        def initialize(actor:, org:, repo_ids_or_query_string:, user_session:)
          @actor = actor
          @org = org
          @repo_ids_or_query_string = repo_ids_or_query_string
          @user_session = user_session
        end

        sig { returns(T.nilable(MultiRepoEnablementContentComponent::Data)) }
        memoize def content_component_data
          return if repo_authorizer.nil?

          MultiRepoEnablementContentComponent::Data.new(
            organization: @org,
            dependency_graph: dependency_graph_feature_data,
            dependabot_alerts: dependabot_alerts_feature_data,
            dependabot_security_updates: dependabot_security_updates_feature_data,
            advanced_security: advanced_security.feature_data,
            codeql_default_setup: codeql_default_setup_feature_data,
            secret_scanning_alerts: secret_scanning_alerts_feature_data,
            secret_scanning_push_protection: secret_scanning_push_protection_feature_data
          )
        end

        sig { returns(ActiveRecord::Relation) }
        memoize def repository_security_center_config_scope
          if repo_ids_or_query_string.is_a?(String)
            return Coverage::ListDataQuery.for_organization(
              organization: org,
              page_size: 0,
              parser: ::Search::Queries::SecurityCenter::CoverageQueryParser.new(T.cast(repo_ids_or_query_string, String)),
              user: actor,
              user_session: user_session
            ).all
          end

          RepositorySecurityCenterConfig
            .where(owner_id: org.id)
            .where(repository_id: repo_ids_or_query_string)
        end

        private

        sig { returns(T.untyped) }
        memoize def advanced_security
          AdvancedSecurity.new(
            actor: actor,
            blocked_by_policy_message: blocked_by_policy_message(docs_path: "/get-started/learning-about-github/about-github-advanced-security"),
            blocked_settings: blocked_settings,
            org: org,
            repo_authorizer: repo_authorizer,
            repository_security_center_config_scope: repository_security_center_config_scope
          )
        end

        sig { returns(BlockedSettings) }
        memoize def blocked_settings
          BlockedSettings.new(org)
        end

        sig { params(docs_path: T.nilable(String)).returns(String) }
        def blocked_by_policy_message(docs_path: nil)
          return BLOCKED_BY_POLICY_MESSAGE if docs_path.blank?

          safe_join([
            BLOCKED_BY_POLICY_MESSAGE,
            " ",
            ActionController::Base.helpers.link_to("Learn more about this policy", "#{docs_base_url}#{docs_path}"),
            "."
          ])
        end

        sig { returns(String) }
        memoize def docs_base_url
          GitHub.help_url(ghec_exclusive: org.business || org.business_plus?)
        end

        # Enterprise policies may block repo admins from modifying security features on all repos.
        #
        # Per the authz rules for the security Coverage page, if the actor is a repo admin on any of the selected repos,
        # then the actor must be a repo admin on all of the repos.
        #
        # Thus, if an enterprise policy blocks the actor from managing a security feature on one of the selected repos,
        # then the actor is blocked from managing that security feature on all of the repos.
        #
        # Authorizer also handles the org owner and security manager distinction, so we don't need that condition here.
        sig { returns(T.nilable(Repository)) }
        memoize def first_adminable_repo
          adminable_repo_ids =
            if SecurityProduct::Permissions::OrgAuthz.new(org, actor:).can_manage_security_products?
              # if the user is an org owner or security manager, they can admin all repositories
              # pick the id of any active repository; the limit/pluck here ensures we don't apply unnecessary ordering
              org.repositories.active.limit(1).pluck(:id)
            else
              actor.associated_repository_ids(min_action: :admin, organization: org) # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
            end

          ::Repositories::Public.find_active(adminable_repo_ids.first) if adminable_repo_ids.any?
        end

        sig { returns(T.nilable(SecurityProduct::Permissions::RepoAuthz)) }
        memoize def repo_authorizer
          return nil if first_adminable_repo.nil?
          SecurityProduct::Permissions::RepoAuthz.new(T.must(first_adminable_repo), actor:)
        end

        sig do
          params(
            blocked_reason: T.nilable(String),
            can_disable: T::Boolean,
            can_enable: T::Boolean,
            description: String,
            is_available: T::Boolean
          ).returns(MultiRepoEnablementContentComponent::FeatureData)
        end
        def get_feature_data(blocked_reason:, can_disable:, can_enable:, description:, is_available:)
          is_blocked = !can_disable && !can_enable

          MultiRepoEnablementContentComponent::FeatureData.new(
            blocked_reason: (blocked_reason if is_blocked),
            can_disable: can_disable,
            can_enable: can_enable,
            description: description,
            is_available: is_available
          )
        end

        sig { returns(MultiRepoEnablementContentComponent::FeatureData) }
        memoize def dependency_graph_feature_data
          can_modify = !dependabot_blocked_by_policy? && !GitHub.enterprise?
          description = "Understand your dependencies."
          description += " Dependency graph is always enabled for public repositories." unless GitHub.enterprise?

          get_feature_data(
            blocked_reason: blocked_by_policy_message(docs_path: "/code-security/supply-chain-security/understanding-your-software-supply-chain/about-the-dependency-graph"),
            can_disable: can_modify,
            can_enable: can_modify,
            description: description,
            is_available: GitHub.dependency_graph_enabled?
          )
        end

        sig { returns(MultiRepoEnablementContentComponent::FeatureData) }
        memoize def dependabot_alerts_feature_data
          can_modify = !dependabot_blocked_by_policy?

          get_feature_data(
            blocked_reason: blocked_by_policy_message(docs_path: "/code-security/dependabot/dependabot-alerts/about-dependabot-alerts"),
            can_disable: can_modify,
            can_enable: can_modify,
            description: "Receive alerts for vulnerabilities that affect your dependencies.",
            is_available: SecurityProduct::VulnerabilityAlerts.enabled_for_instance?
          )
        end

        sig { returns(MultiRepoEnablementContentComponent::FeatureData) }
        memoize def dependabot_security_updates_feature_data
          can_modify = !dependabot_blocked_by_policy?

          get_feature_data(
            blocked_reason: blocked_by_policy_message(docs_path: "/code-security/dependabot/dependabot-security-updates/about-dependabot-security-updates"),
            can_disable: can_modify,
            can_enable: can_modify,
            description: "Automatically open pull requests to resolve Dependabot alerts.",
            is_available: GitHub.dependabot_enabled?
          )
        end

        sig { returns(MultiRepoEnablementContentComponent::FeatureData) }
        memoize def codeql_default_setup_feature_data
          can_modify = !blocked_settings.code_scanning?

          get_feature_data(
            blocked_reason: BLOCKED_SETTINGS_MESSAGE,
            can_disable: can_modify,
            can_enable: can_modify,
            description: safe_join([
              "Identify vulnerabilities and errors with ",
              ActionController::Base.helpers.link_to("CodeQL", "#{GitHub.help_url(ghec_exclusive: true)}/code-security/code-scanning/automatically-scanning-your-code-for-vulnerabilities-and-errors/about-code-scanning-with-codeql"),
              " for ",
              ActionController::Base.helpers.link_to("eligible", "#{GitHub.help_url(ghec_exclusive: true)}/code-security/code-scanning/automatically-scanning-your-code-for-vulnerabilities-and-errors/configuring-code-scanning-at-scale#eligible-repositories-for-codeql-default-setup"),
              " repositories. This will automatically find the best configuration for your selected repositories based on the chosen ",
              ActionController::Base.helpers.link_to("query suite", built_in_codeql_query_suites_docs_path(org)),
              "."
            ]),
            is_available: ::SecurityCenter::SecurityFeatures.code_scanning_enabled_for_instance?
          )
        end

        sig { returns(MultiRepoEnablementContentComponent::FeatureData) }
        memoize def secret_scanning_alerts_feature_data
          can_modify = !secret_scanning_blocked_by_policy? && !blocked_settings.secret_scanning?
          secret_scanning_alerts_blocked_reason =
            if secret_scanning_blocked_by_policy?
              blocked_by_policy_message(docs_path: "/code-security/secret-scanning/about-secret-scanning")
            elsif blocked_settings.secret_scanning?
              BLOCKED_SETTINGS_MESSAGE
            end

          get_feature_data(
            blocked_reason: secret_scanning_alerts_blocked_reason,
            can_disable: can_modify,
            can_enable: can_modify,
            description: safe_join([
              "Receive alerts on GitHub for detected secrets, keys, or other tokens. ",
              "GitHub will always send alerts to partners for detected secrets in public repositories. ",
              ActionController::Base.helpers.link_to(
                "Learn more about partner patterns",
                "#{DocsUrlConfig.url_for("code-security/about-secret-scanning-alerts-for-partners", ghec: true)}"
              ),
              "."
            ]),
            is_available: SecretScanning::Features::Owner::TokenScanning.new(org).feature_available?
          )
        end

        sig { returns(MultiRepoEnablementContentComponent::FeatureData) }
        memoize def secret_scanning_push_protection_feature_data
          can_modify = !secret_scanning_blocked_by_policy? && !blocked_settings.push_protection?
          push_protection_blocked_reason =
            if secret_scanning_blocked_by_policy?
              blocked_by_policy_message(docs_path: "/code-security/secret-scanning/protecting-pushes-with-secret-scanning")
            elsif blocked_settings.push_protection?
              BLOCKED_SETTINGS_MESSAGE
            end

          get_feature_data(
            can_disable: can_modify,
            can_enable: can_modify,
            description: "Block commits that contain secrets.",
            is_available: SecretScanning::Features::Owner::PushProtection.new(org).feature_available?,
            blocked_reason: push_protection_blocked_reason
          )
        end

        sig { returns(T::Boolean) }
        memoize def dependabot_blocked_by_policy?
          !!repo_authorizer&.manage_repo_dependabot_alerts_enablement_blocked_by_policy?
        end

        sig { returns(T::Boolean) }
        memoize def secret_scanning_blocked_by_policy?
          !!repo_authorizer&.manage_repo_secret_scanning_settings_blocked_by_policy?
        end

        class AdvancedSecurity
          extend T::Sig
          include GitHub::Memoizer
          include ActionView::Helpers::OutputSafetyHelper

          sig { returns(User) }; attr_reader :actor
          sig { returns(String) }; attr_reader :blocked_by_policy_message
          sig { returns(BlockedSettings) }; attr_reader :blocked_settings
          sig { returns(Organization) }; attr_reader :org
          sig { returns(T.nilable(SecurityProduct::Permissions::RepoAuthz)) }; attr_reader :repo_authorizer
          sig { returns(ActiveRecord::Relation) }; attr_reader :repository_security_center_config_scope

          sig do
            params(
              actor: User,
              blocked_by_policy_message: String,
              blocked_settings: BlockedSettings,
              org: Organization,
              repo_authorizer: T.nilable(SecurityProduct::Permissions::RepoAuthz),
              repository_security_center_config_scope: ActiveRecord::Relation
            ).void
          end
          def initialize(actor:, blocked_by_policy_message:, blocked_settings:, org:, repo_authorizer:, repository_security_center_config_scope:)
            @actor = T.let(actor, User)
            @blocked_by_policy_message = T.let(blocked_by_policy_message, String)
            @blocked_settings = T.let(blocked_settings, BlockedSettings)
            @org = T.let(org, Organization)
            @repo_authorizer = repo_authorizer
            @repository_security_center_config_scope = T.let(repository_security_center_config_scope, ActiveRecord::Relation)
          end

          sig { returns(MultiRepoEnablementContentComponent::FeatureData) }
          memoize def feature_data
            is_blocked = !can_modify? && !can_enable?

            MultiRepoEnablementContentComponent::FeatureData.new(
              blocked_reason: (blocked_message if is_blocked),
              can_disable: can_modify?,
              can_enable: can_enable?,
              description: description,
              is_available: org.advanced_security_configurable?
            )
          rescue AdvancedSecurityLicense::TurboghasError => e
            Failbot.report(e, catalog_service: "github/advanced_security_billing")
            MultiRepoEnablementContentComponent::FeatureData.new(
              blocked_reason: "Unable to determine license usage. Please try again later.",
              can_disable: false,
              can_enable: false,
              description: description_preamble,
              is_available: org.advanced_security_configurable?,
            )
          end

          private

          sig { returns(T::Boolean) }
          memoize def blocked_by_policy?
            !!repo_authorizer&.manage_repo_advanced_security_enablement_blocked_by_policy?
          end

          sig { returns(T.nilable(String)) }
          memoize def blocked_message
            if blocked_by_policy?
              blocked_by_policy_message
            elsif blocked_settings.advanced_security?
              BLOCKED_SETTINGS_MESSAGE
            end
          end

          sig { returns(T::Boolean) }
          memoize def can_enable?
            can_modify? &&
              !enable_blocked_by_policy? &&
              !would_exceed_license_allowance?
          end

          sig { returns(T::Boolean) }
          memoize def can_modify?
            !blocked_by_policy? &&
              !blocked_settings.advanced_security?
          end

          sig { returns(String) }
          memoize def description_preamble
            desc = ["GitHub Advanced Security features are billed per active committer."]
            desc << " The features are free of charge in public repositories." unless GitHub.enterprise?
            safe_join(desc)
          end

          sig { returns(String) }
          memoize def description
            desc = [description_preamble]

            if enable_blocked_by_policy?
              desc << " An enterprise-level policy has restricted enablement."
            elsif would_exceed_license_allowance?
              desc << " You do not have enough licenses to enable GitHub Advanced Security."
            elsif blocked_message.blank?
              out_of_remaining = org.advanced_security_license.unlimited_seats? ? " " : " out of #{org.advanced_security_license.remaining_seats} remaining "
              license_usage = org.advanced_security_license.unlimited_seats? ? "license".pluralize(license_usage_increase) : "licenses"

              desc << " Enabling will use #{license_usage_increase}#{out_of_remaining}GitHub Advanced Security #{license_usage}."
            end

            safe_join(desc)
          end

          sig { returns(T::Boolean) }
          memoize def enable_blocked_by_policy?
            !org.policy_allows_advanced_security_enablement?
          end

          # The number of licenses that would be used if GHAS is enabled on the selected repositories.
          sig { returns(Integer) }
          memoize def license_usage_increase
            GitHub.dogstats.distribution_time("security_center.multi_repo_enablement.advanced_security.license_usage_increase") do
              repo_ids = repository_security_center_config_scope.pluck(:repository_id)

              org.advanced_security_license.seat_usage_increase_if_advanced_security_enabled_for_repos(repo_ids)
            end
          end

          # Would license usage exceed the enterprise's limit if GHAS is enabled on the selected repositories?
          sig { returns(T::Boolean) }
          memoize def would_exceed_license_allowance?
            return false unless org.enforce_advanced_security_committers_limits?
            return false unless org.advanced_security_purchased?
            return false if org.advanced_security_license.unlimited_seats?
            return true if org.advanced_security_license.allowance_exceeded?
            license_usage_increase > org.advanced_security_license.remaining_seats
          end
        end
      end
    end
  end
end
