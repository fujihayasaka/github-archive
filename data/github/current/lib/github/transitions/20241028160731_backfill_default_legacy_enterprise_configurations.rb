# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillDefaultLegacyEnterpriseConfigurations < Base
      include GitHub::Memoizer

      class SecurityConfiguration < ApplicationRecord::Notify
        # Where are :name and :description defined?
        self.table_name = :security_configurations
        belongs_to :target, polymorphic: true
        has_many :security_configuration_defaults, dependent: :delete_all, inverse_of: :security_configuration

        FEATURE_STATES = T.let({ disabled: 0, enabled: 1, not_set: 2 }, T::Hash[T.untyped, T.untyped])
        enum :private_vulnerability_reporting, FEATURE_STATES, prefix: true, validate: true
        enum :dependency_graph, FEATURE_STATES, prefix: true, validate: true
        enum :dependency_graph_autosubmit_action, FEATURE_STATES, prefix: true, validate: true
        enum :dependabot_alerts, FEATURE_STATES, prefix: true, validate: true
        enum :dependabot_security_updates, FEATURE_STATES, prefix: true, validate: true
        enum :code_scanning, FEATURE_STATES, prefix: true, validate: true
        enum :secret_scanning, FEATURE_STATES, prefix: true, validate: true
        enum :secret_scanning_push_protection, FEATURE_STATES, prefix: true, validate: true
        enum :secret_scanning_delegated_bypass, FEATURE_STATES, prefix: true, validate: true
        enum :secret_scanning_validity_checks, FEATURE_STATES, prefix: true, validate: { allow_nil: true }
        enum :secret_scanning_non_provider_patterns, FEATURE_STATES, prefix: true, validate: { allow_nil: true }
        enum :secret_scanning_generic_secrets, FEATURE_STATES, prefix: true, validate: { allow_nil: true }
      end

      class SecurityConfigurationDefault < ApplicationRecord::Notify
        belongs_to :security_configuration, inverse_of: :security_configuration_defaults
        belongs_to :target, polymorphic: true

        sig do
          params(
            target: T.any(User, Business),
            default_for_new_public_repos: T::Boolean,
            default_for_new_private_repos: T::Boolean,
            security_configuration: SecurityConfiguration,
          ).void
        end
        def self.create_or_update_defaults(
          target:,
          default_for_new_public_repos:,
          default_for_new_private_repos:,
          security_configuration:
        )
          defaults = self.where(target: target)
          security_configuration_id = security_configuration.id

          return if defaults.where(
            security_configuration_id:, default_for_new_public_repos:, default_for_new_private_repos:
          ).exists?

          ActiveRecord::Base.connected_to(role: :writing) do
            transaction do
              skip = false
              if default_for_new_public_repos && default_for_new_private_repos
                defaults.each(&:destroy!)
              elsif default_for_new_public_repos || default_for_new_private_repos
                # default_for_new_public_repos
                defaults.where(default_for_new_public_repos: true, default_for_new_private_repos: false).first&.destroy if default_for_new_public_repos
                # default_for_new_private_repos
                defaults. where(default_for_new_public_repos: false, default_for_new_private_repos: true).first&.destroy if default_for_new_private_repos

                # default_for_new_public_and_private_repos
                default_record = defaults. where(default_for_new_public_repos: true, default_for_new_private_repos: true) .first
                if default_record.present?
                  if default_record.security_configuration_id == security_configuration_id
                    # When config A is the default for all repos,
                    # and we change it to only be the default for either public or private repos,
                    # then we can just update the existing record for the config with the given values.
                    default_record.update(
                      default_for_new_public_repos: default_for_new_public_repos,
                      default_for_new_private_repos: default_for_new_private_repos
                    )
                  else
                    # When config A is the default for all repos,
                    # and we are setting config B as default for only either public or private repos,
                    # then we update the existing record to be the default for the other type of repos.
                    default_record.update(
                      default_for_new_public_repos: !default_for_new_public_repos,
                      default_for_new_private_repos: !default_for_new_private_repos
                    )
                  end
                end
              else
                # If the configuration belongs to an organization, we can destroy the defaults and skip creating a new one
                # for cases where the default is not set.
                #
                # However, if the configuration belongs to an enterprise and we're setting a default for an organization,
                # we need to create a record with the defaults set to false for both public & private,
                # which means we can not skip record updating like we do with org-level configs.
                unless T.unsafe(security_configuration).belongs_to_enterprise? && target.is_a?(Organization)
                  defaults.find_by(target:, security_configuration_id:)&.destroy
                  # In transactions, the usage of `return`, `break`, or `throw` is being deprecated and causes test failures.
                  # Hence the usage of `skip` boolean value here, to skip creating/updating defaults if both defaults are false
                  skip = true
                end
              end

              unless skip
                default = find_or_initialize_by(target:, security_configuration_id:)
                # Even if the record is freshly initialized, `update` will persist it with the updated values:
                default.update(
                  default_for_new_public_repos:,
                  default_for_new_private_repos:
                )
              end
            end
          end
        end
      end


      BASE_QUERY_CONDITION = "suspended_at IS NULL AND deleted_at IS NULL"

      iterate_over :database_table, params: {
        model_class: Business,
        conditions: BASE_QUERY_CONDITION,
        columns: %i[id],
      }

      sig do
        override.params(
          message: String,
          payload: T::Hash[T.any(Symbol, String), T.untyped]
        ).void
      end
      def log(message, payload = {})
        logger.with_named_tags("code.namespace" => "GitHub::Transitions::BackfillDefaultLegacyEnterpriseConfigurations") do
          super(message, payload)
        end
      end

      sig { override.void }
      def after_initialize
        # in some scenarios, loading the license will trigger a write to the Business table
        # that must happen with a write connection so let's preload the license for the instance
        # it's not possible to write a unit test for this since in test, we mock the license object :(
        write_to(model_class: Business) { GitHub::Enterprise.license } if GitHub.enterprise? && !dry_run?

        return unless arguments[:business_ids].present?

        iterator = T.cast(self.iterator, Iterators::DatabaseTable)
        iterator.conditions = BASE_QUERY_CONDITION + " AND id IN (#{arguments[:business_ids]})"
      end

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        businesses = Business.where(id: items.keys).to_a
        businesses = Configurable.preload_configuration(businesses)

        month_and_year = Time.current.strftime("%B %Y")
        businesses.each { |biz| create_default_configs(biz, month_and_year) }
      end

      sig { params(business: Business, month_and_year: String).void }
      def create_default_configs(business, month_and_year)
        unless any_features_enabled_by_default?(business)
          log "Business #{business.id} - no features enabled, skipping"
          return
        end

        if ::SecurityConfigurationDefault.where(target: business).exists?
          log "Business #{business.id} - default config already exists, skipping"
          return
        end

        base_features_hash = {
          dependency_graph: feature_default_values[:dependency_graph],
          dependency_graph_autosubmit_action: feature_default_values[:dependency_graph_autosubmit_action],
          dependabot_alerts: feature_default_values[:dependabot_alerts],
          dependabot_security_updates: feature_default_values[:dependabot_security_updates],
          private_vulnerability_reporting: feature_default_values[:private_vulnerability_reporting],
          enable_ghas: T.let(false, T::Boolean),
          code_scanning: :disabled,
          secret_scanning: :disabled,
          secret_scanning_push_protection: :disabled,
          secret_scanning_non_provider_patterns: :disabled,
          secret_scanning_delegated_bypass: :disabled,
          secret_scanning_validity_checks: :disabled,
          secret_scanning_generic_secrets: :disabled,
          secret_scanning_delegated_alert_dismissal: :disabled,
        }

        # In GHES, Dependency Graph could be enabled for the entire instance.
        # But Dependabot alerts may not be set to auto-enable.
        if GitHub.enterprise? && GitHub.dependency_graph_enabled?
          base_features_hash[:dependency_graph] = :enabled
        end

        if dependabot_alerts_enabled_for_new_repos?(business)
          base_features_hash[:dependency_graph] = :enabled
          base_features_hash[:dependabot_alerts] = :enabled
        end

        if business.advanced_security_enabled_on_new_repos?
          base_features_hash[:enable_ghas] = true
        end

        # We need to create a separate default configs for public and private repos in the following cases:
        # 1. The business has GHAS, and GHAS is not enabled automatically for new repos, but secret scanning is
        # 2. The business does not have GHAS, but secret scanning is automatically enabled for new public repos
        #
        # Separate configs are needed because we should not enable GHAS for private repos in these cases.
        #
        # Also, this is only a concern in Dotcom, and not Proxima and GHES.
        features_for_public_repos = {}
        features_for_private_repos = {}
        create_configs_by_repo_visibility = false

        token_scanning = SecretScanning::Features::Business::TokenScanning.new(business)
        push_protection = SecretScanning::Features::Business::PushProtection.new(business)
        lower_confidence_patterns = SecretScanning::Features::Business::LowerConfidencePatterns.new(business)
        validity_checks = SecretScanning::Features::Business::ValidityChecks.new(business)

        if token_scanning.secret_scanning_enabled_for_new_repos?
          if base_features_hash[:enable_ghas]
            base_features_hash[:secret_scanning] = :enabled
            base_features_hash[:secret_scanning_push_protection] = push_protection.enabled_for_new_repos? ? :enabled : T.must(feature_default_values[:secret_scanning_push_protection])
            base_features_hash[:secret_scanning_non_provider_patterns] = lower_confidence_patterns.enabled_for_new_repos? ? :enabled : T.must(feature_default_values[:secret_scanning_non_provider_patterns])
            base_features_hash[:secret_scanning_validity_checks] = validity_checks.enabled_for_new_repos? ? :enabled : T.must(feature_default_values[:secret_scanning_validity_checks])
            base_features_hash[:secret_scanning_delegated_bypass] = T.must(feature_default_values[:secret_scanning_delegated_bypass])
          elsif !GitHub.single_or_multi_tenant_enterprise?
            features_for_public_repos = base_features_hash.dup
            features_for_private_repos = base_features_hash.dup
            create_configs_by_repo_visibility = true

            features_for_public_repos[:enable_ghas] = true
            features_for_public_repos[:secret_scanning] = :enabled
            features_for_public_repos[:secret_scanning_push_protection] = push_protection.enabled_for_new_repos? ? :enabled : T.must(feature_default_values[:secret_scanning_push_protection])
            features_for_public_repos[:secret_scanning_non_provider_patterns] = lower_confidence_patterns.enabled_for_new_repos? ? :enabled : T.must(feature_default_values[:secret_scanning_non_provider_patterns])
            features_for_public_repos[:secret_scanning_validity_checks] = validity_checks.enabled_for_new_repos? ? :enabled : T.must(feature_default_values[:secret_scanning_validity_checks])
            features_for_public_repos[:secret_scanning_delegated_bypass] = T.must(feature_default_values[:secret_scanning_delegated_bypass])
          end
        end

        # At the beginning, we set GHAS and GHAS features to be disabled by default.
        # After that, if GHAS was set to "enabled" in the config, AND GHAS features are still set as "disabled",
        # we want to see if they can be changed to "not_set" because it is more permissive.
        if create_configs_by_repo_visibility
          features_for_public_repos[:code_scanning] = T.must(feature_default_values[:code_scanning]) if features_for_public_repos[:enable_ghas]
        elsif base_features_hash[:enable_ghas]
          %i[secret_scanning secret_scanning_push_protection secret_scanning_non_provider_patterns secret_scanning_validity_checks secret_scanning_delegated_bypass code_scanning].each do |feature|
            base_features_hash[feature] = T.must(feature_default_values[feature]) if base_features_hash[feature] == :disabled
          end
        end

        if create_configs_by_repo_visibility
          log "Business #{business.id} - default config for public repos - #{features_for_public_repos}"
          log "Business #{business.id} - default config for private repos - #{features_for_private_repos}"
        else
          log "Business #{business.id} - default config for all repos - #{base_features_hash}"
        end

        return if dry_run?

        write_to(model_class: SecurityConfiguration) do
          if create_configs_by_repo_visibility
            public_config = SecurityConfiguration.create!(
              target: business,
              name: "Public Repository Default Settings",
              description: "This configuration includes your previous enterprise-level default settings for new public repositories as of #{month_and_year}. It will be applied if no organization-level defaults are set.",
              **features_for_public_repos
            )
            log "Business #{business.id} - created public config"

            private_config = SecurityConfiguration.create!(
              target: business,
              name: "Private/Internal Repository Default Settings",
              description: "This configuration includes your previous enterprise-level default settings for new private/internal repositories as of #{month_and_year}. It will be applied if no organization-level defaults are set.",
              **features_for_private_repos
            )
            log "Business #{business.id} - created private config"

            SecurityConfigurationDefault.create_or_update_defaults(
              target: business,
              default_for_new_public_repos: true,
              default_for_new_private_repos: false,
              security_configuration: public_config,
            )
            log "Business #{business.id} - created default for public repos"

            SecurityConfigurationDefault.create_or_update_defaults(
              target: business,
              default_for_new_public_repos: false,
              default_for_new_private_repos: true,
              security_configuration: private_config,
            )
            log "Business #{business.id} - created default for private repos"
          else
            security_configuration = SecurityConfiguration.create!(
              target: business,
              name: "New Repository Default Settings",
              description: "This configuration includes your previous enterprise-level default settings for new repositories as of #{month_and_year}. It will be applied if no organization-level defaults are set.",
              **base_features_hash
            )
            log "Business #{business.id} - created config"

            SecurityConfigurationDefault.create_or_update_defaults(
              target: business,
              default_for_new_public_repos: !GitHub.multi_tenant_enterprise?,
              default_for_new_private_repos: true,
              security_configuration: security_configuration,
            )
            log "Business #{business.id} - created default for all repos"
          end
        end
      end

      sig { params(business: Business).returns(T::Boolean) }
      def any_features_enabled_by_default?(business)
        token_scanning = SecretScanning::Features::Business::TokenScanning.new(business)
        push_protection = SecretScanning::Features::Business::PushProtection.new(business)
        lower_confidence_patterns = SecretScanning::Features::Business::LowerConfidencePatterns.new(business)
        validity_checks = SecretScanning::Features::Business::ValidityChecks.new(business)

        dependabot_alerts_enabled_for_new_repos?(business) ||
          business.advanced_security_enabled_on_new_repos? ||
          token_scanning.secret_scanning_enabled_for_new_repos? ||
          push_protection.enabled_for_new_repos? ||
          lower_confidence_patterns.enabled_for_new_repos? ||
          validity_checks.enabled_for_new_repos?
      end

      sig { params(business: Business).returns(T::Boolean) }
      def dependabot_alerts_enabled_for_new_repos?(business)
        business.security_alerts_enabled_for_new_repos? && security_products_manager.dependabot_alerts_enabled?
      end

      # This method tries to encapsulate the logic of whether a feature should be not_set or disabled.
      # When a feature is not enabled by default, we may want to set it to "not_set".
      # However, because of feature availability in different environments, sometimes we need to set it to "disabled".
      sig { returns(T::Hash[Symbol, Symbol]) }
      memoize def feature_default_values
        secret_scanning_default_value = security_products_manager.secret_scanning_enabled? ? :not_set : :disabled
        {
          dependency_graph: security_products_manager.dependency_graph_enabled? ? :not_set : :disabled,
          dependency_graph_autosubmit_action: security_products_manager.dependency_graph_autosubmit_action_enabled? ? :not_set : :disabled,
          dependabot_alerts: security_products_manager.dependabot_alerts_enabled? ? :not_set : :disabled,
          dependabot_security_updates: security_products_manager.dependabot_security_updates_enabled? ? :not_set : :disabled,
          private_vulnerability_reporting: security_products_manager.private_vulnerability_reporting_enabled? ? :not_set : :disabled,
          code_scanning: security_products_manager.code_scanning_default_setup_enabled? ? :not_set : :disabled,
          secret_scanning: secret_scanning_default_value,
          secret_scanning_push_protection: secret_scanning_default_value,
          secret_scanning_non_provider_patterns: secret_scanning_default_value,
          secret_scanning_delegated_bypass: secret_scanning_default_value,
          secret_scanning_validity_checks: secret_scanning_default_value,
        }
      end

      sig { returns(SecurityProductsEnablement::SecurityProductsManager) }
      memoize def security_products_manager
        SecurityProductsEnablement::SecurityProductsManager.new
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV, additional_arguments: %w(business_ids))

  GitHub::Transitions::BackfillDefaultLegacyEnterpriseConfigurations.new(args).run
end
