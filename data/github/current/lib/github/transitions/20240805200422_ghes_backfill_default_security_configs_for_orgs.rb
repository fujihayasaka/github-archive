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
        if ::SecurityConfigurationDefault.for_organization(org).exists?
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
            security_configuration_id: T.must(security_configuration.id),
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
