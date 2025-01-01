# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class GhesBackfillDefaultSecurityConfigsForOrgs < Base
      class User < ApplicationRecord::Domain::Users
        self.table_name = :users
      end

      class SecurityConfiguration < ApplicationRecord::Notify
        self.table_name = :security_configurations
        belongs_to :target, polymorphic: true
        has_many :security_configuration_defaults, dependent: :delete_all, inverse_of: :security_configuration

        FEATURE_STATES = T.let({ disabled: 0, enabled: 1, not_set: 2 }, T::Hash[T.untyped, T.untyped])
        enum :private_vulnerability_reporting, FEATURE_STATES, prefix: true, validate: true
        enum :dependency_graph, FEATURE_STATES, prefix: true, validate: true
        enum :dependency_graph_autosubmit_action, FEATURE_STATES, prefix: true, validate: { allow_nil: true }
        enum :dependabot_alerts, FEATURE_STATES, prefix: true, validate: true
        enum :dependabot_security_updates, FEATURE_STATES, prefix: true, validate: true
        enum :code_scanning, FEATURE_STATES, prefix: true, validate: true
        enum :secret_scanning, FEATURE_STATES, prefix: true, validate: true
        enum :secret_scanning_push_protection, FEATURE_STATES, prefix: true, validate: true
        enum :secret_scanning_validity_checks, FEATURE_STATES, prefix: true, validate: { allow_nil: true }
        enum :secret_scanning_non_provider_patterns, FEATURE_STATES, prefix: true, validate: { allow_nil: true }
        # DO NOT ADD NEW FIELDS HERE! These enums should match the state of the model on 2024-08-05!

        # This block allows us to set a default value for columns that don't exist in the initial version of the
        # database, but exit in notify-structure.sql. This lets the tests pass without a default value in the DB.
        if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
          attribute :secret_scanning_delegated_bypass, default: FEATURE_STATES[:not_set]
        end
      end

      class SecurityConfigurationDefault < ApplicationRecord::Notify
        belongs_to :security_configuration, inverse_of: :security_configuration_defaults
        belongs_to :target, polymorphic: true

        scope :for_organization, -> (o) { where(target: o) }

        sig do
          params(
            target: T.any(::Organization, User),
            default_for_new_public_repos: T::Boolean,
            default_for_new_private_repos: T::Boolean,
            security_configuration_id: Integer,
          ).void
        end
        def self.create_or_update_defaults(
          target:,
          default_for_new_public_repos:,
          default_for_new_private_repos:,
          security_configuration_id:
        )
          defaults = for_organization(target)

          return if defaults.where(
            security_configuration_id:, default_for_new_public_repos:, default_for_new_private_repos:
          ).exists?

          ActiveRecord::Base.connected_to(role: :writing) do
            transaction do
              skip = false
              if default_for_new_public_repos && default_for_new_private_repos
                defaults.each(&:destroy!)
              elsif default_for_new_public_repos || default_for_new_private_repos
                defaults.default_for_new_public_repos.first&.destroy if default_for_new_public_repos
                defaults.default_for_new_private_repos.first&.destroy if default_for_new_private_repos

                default_record = defaults.default_for_new_public_and_private_repos.first
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
                defaults.find_by(target:, security_configuration_id:)&.destroy
                # In transactions, the usage of `return`, `break`, or `throw` is being deprecated and causes test failures.
                # Hence the usage of `skip` boolean value here, to skip creating/updating defaults if both defaults are false
                skip = true
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

      iterate_over :database_table, params: {
        model_class: User,
        conditions: "type = 'Organization'",
        columns: %i[id],
      }

      sig do
        override.params(
          message: String,
          payload: T::Hash[T.any(Symbol, String), T.untyped]
        ).void
      end
      def log(message, payload = {})
        logger.with_named_tags("code.namespace" => "GitHub::Transitions::GhesBackfillDefaultSecurityConfigsForOrgs") do
          super(message, payload)
        end
      end

      sig { override.void }
      def after_initialize
        # in some scenarios, loading the license will trigger a write to the Business table
        # that must happen with a write connection so let's preload the license for the instance
        # it's not possible to write a unit test for this since in test, we mock the license object :(
        write_to(model_class: Business) { GitHub::Enterprise.license } unless dry_run?

        return unless arguments[:org_ids].present?

        iterator = T.cast(self.iterator, Iterators::DatabaseTable)
        iterator.conditions = "type = 'Organization' AND id IN (#{arguments[:org_ids]})"
      end

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        orgs = ::Organization.where(id: items.keys, type: "Organization").to_a
        orgs.select! { |org| !org.disabled && !org.spammy && org.suspended_at.nil? && org.archived_at.nil? }

        log "Processing #{orgs.size} organizations"

        orgs.each do |org|
          logger.with_named_tags("gh.org.id": org.id) do
            create_default_configs(org)
          end
        end
      end

      sig { params(org: ::Organization).void }
      def create_default_configs(org)
        unless any_features_enabled_by_default?(org)
          log "skipping, no features enabled by default"
          return
        end

        # Skip if there is already a configuration default for the org
        if SecurityConfigurationDefault.for_organization(org).exists?
          log "skipping, already has a default security configuration"
          return
        end

        # Default state of config for an org with no previous settings enabled
        base_features_hash = {
          dependency_graph: :disabled,
          dependency_graph_autosubmit_action: :disabled,
          dependabot_alerts: :disabled,
          dependabot_security_updates: :disabled,
          private_vulnerability_reporting: :disabled,
          enable_ghas: T.let(false, T::Boolean),
          code_scanning: :disabled,
          secret_scanning: :disabled,
          secret_scanning_push_protection: :disabled,
          secret_scanning_validity_checks: :disabled,
          secret_scanning_non_provider_patterns: :disabled,
          # IMPORTANT: DO NOT ADD FEATURES HERE!
        }

        # Create service manager instance to check if the desired services are enabled in the instance
        service_manager = SecurityProductsEnablement::SecurityProductsManager.new

        if service_manager.dependabot_security_updates_enabled? && org.vulnerability_updates_enabled_for_new_repos?
          base_features_hash[:dependabot_security_updates] = :enabled
          base_features_hash[:dependabot_alerts] = :enabled
          base_features_hash[:dependency_graph] = :enabled
        end

        if service_manager.dependabot_alerts_enabled? && org.security_alerts_enabled_for_new_repos?
          base_features_hash[:dependabot_alerts] = :enabled
          base_features_hash[:dependency_graph] = :enabled
        end

        if service_manager.dependency_graph_enabled? && org.dependency_graph_enabled_for_new_repos?
          base_features_hash[:dependency_graph] = :enabled
        end

        if org.advanced_security_purchased? && org.advanced_security_enabled_on_new_repos?
          base_features_hash[:enable_ghas] = true
        end

        token_scanning = SecretScanning::Features::Org::TokenScanning.new(org)
        if service_manager.secret_scanning_enabled? && token_scanning.secret_scanning_enabled_for_new_repos?
          push_protection_enabled_for_new_repos = SecretScanning::Features::Org::PushProtection.new(org).enabled_for_new_repos?
          non_provider_patterns_enabled_for_new_repos = SecretScanning::Features::Org::LowerConfidencePatterns.new(org).enabled?

          if base_features_hash[:enable_ghas]
            base_features_hash[:secret_scanning] = :enabled
            base_features_hash[:secret_scanning_push_protection] = push_protection_enabled_for_new_repos ? :enabled : :not_set
            base_features_hash[:secret_scanning_non_provider_patterns] = non_provider_patterns_enabled_for_new_repos ? :enabled : :not_set
          else
            base_features_hash[:enable_ghas] = false
            base_features_hash[:secret_scanning] = :disabled
            base_features_hash[:secret_scanning_push_protection] = :disabled
            base_features_hash[:secret_scanning_non_provider_patterns] = :disabled
          end
        end

        if base_features_hash[:enable_ghas]
          base_features_hash[:secret_scanning] = :not_set if service_manager.secret_scanning_enabled? && base_features_hash[:secret_scanning] == :disabled
          base_features_hash[:secret_scanning_push_protection] = :not_set if service_manager.secret_scanning_enabled? && base_features_hash[:secret_scanning_push_protection] == :disabled
          base_features_hash[:secret_scanning_non_provider_patterns] = :not_set if service_manager.secret_scanning_enabled? && base_features_hash[:secret_scanning_non_provider_patterns] == :disabled
          base_features_hash[:code_scanning] = :not_set if service_manager.code_scanning_default_setup_enabled? && base_features_hash[:code_scanning] == :disabled
        end

        log "creating default security configuration with: #{base_features_hash}"

        return if dry_run?

        write_to(model_class: SecurityConfiguration) do
          security_configuration = SecurityConfiguration.create!(
            target: org,
            name: "New Repository Default Settings",
            description: "This configuration includes your previous organization-level default settings for new repositories as of when configurations became available",
            **base_features_hash
          )

          SecurityConfigurationDefault.create_or_update_defaults(
            target: org,
            default_for_new_public_repos: true,
            default_for_new_private_repos: true,
            security_configuration_id: security_configuration.id,
          )
        end

        log "created default security configuration"
      end

      sig { params(org: ::Organization).returns(T::Boolean) }
      def any_features_enabled_by_default?(org)
        token_scanning = SecretScanning::Features::Org::TokenScanning.new(org)
        push_protection = SecretScanning::Features::Org::PushProtection.new(org)

        org.vulnerability_updates_enabled_for_new_repos? ||
          org.security_alerts_enabled_for_new_repos? ||
          org.dependency_graph_enabled_for_new_repos? ||
          org.advanced_security_enabled_on_new_repos? ||
          token_scanning.secret_scanning_enabled_for_new_repos? ||
          push_protection.enabled_for_new_repos?
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::GhesBackfillDefaultSecurityConfigsForOrgs.new(args).run
end
