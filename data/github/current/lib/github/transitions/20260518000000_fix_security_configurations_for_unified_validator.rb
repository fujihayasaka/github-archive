# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# Fixes SecurityConfiguration records whose feature settings will fail the
# new unified validator. Seven categories of fixes:
#
# Fix 1: secret_scanning_extended_metadata = enabled while secret_protection_sku_enabled = false
#         (unbundled configs only) → set extended_metadata to disabled
#
# Fix 2: dependabot_delegated_alert_dismissal = enabled while code_security_sku_enabled IS NULL or false
#         (unbundled configs only) → set delegated_alert_dismissal to disabled
#
# Fix 3: secret_scanning_validity_checks = disabled AND secret_scanning_extended_metadata = not_set
#         (all config types) → set extended_metadata to disabled
#
# Fix 4: code_scanning_delegated_alert_dismissal = not_set while code_security_sku_enabled = false
#         (unbundled configs only) → set cs_delegated_alert_dismissal to disabled
#
# Fix 5: dependabot_delegated_alert_dismissal = not_set while code_security_sku_enabled = false
#         (unbundled configs only) → set dg_delegated_alert_dismissal to disabled
#
# Fix 6: secret_protection features enabled while secret_protection_sku_enabled IS NULL
#         (unbundled configs only) → set each enabled SP feature to not_set
#
# Fix 7: code_scanning or code_scanning_delegated_alert_dismissal enabled while
#         code_security_sku_enabled IS NULL (unbundled configs only) → set to not_set
#
# This transition emits security_configuration.update audit log events for each
# modified record via ActiveRecord after_commit callbacks.
module GitHub
  module Transitions
    class FixSecurityConfigurationsForUnifiedValidator < Base
      include GitHub::Memoizer

      # Lightweight model for the iterator — the real SecurityConfiguration model
      # is used for updates so that after_commit hooks (audit logging) fire.
      class SecurityConfig < ApplicationRecord::Notify
        self.table_name = :security_configurations
      end

      # disabled = 0, enabled = 1, not_set = 2
      DISABLED = 0
      ENABLED = 1
      NOT_SET = 2

      # SP features that can be individually enabled — checked for Fix 6.
      SP_FEATURE_COLUMNS = T.let(%i[
        secret_scanning
        secret_scanning_push_protection
        secret_scanning_validity_checks
        secret_scanning_non_provider_patterns
        secret_scanning_generic_secrets
        secret_scanning_delegated_alert_dismissal
        secret_scanning_extended_metadata
        secret_scanning_delegated_bypass
      ].freeze, T::Array[Symbol])

      # CS features that can be individually enabled — checked for Fix 7.
      CS_FEATURE_COLUMNS = T.let(%i[
        code_scanning
        code_scanning_delegated_alert_dismissal
      ].freeze, T::Array[Symbol])

      iterate_over :database_table, params: {
        model_class: SecurityConfig,
        conditions: <<~SQL.squish,
          (type = 'UnbundledSecurityConfiguration' AND secret_scanning_extended_metadata = #{ENABLED} AND secret_protection_sku_enabled = 0)
          OR (type = 'UnbundledSecurityConfiguration' AND dependabot_delegated_alert_dismissal = #{ENABLED} AND (code_security_sku_enabled IS NULL OR code_security_sku_enabled = 0))
          OR (secret_scanning_validity_checks = #{DISABLED} AND secret_scanning_extended_metadata = #{NOT_SET})
          OR (type = 'UnbundledSecurityConfiguration' AND code_scanning_delegated_alert_dismissal = #{NOT_SET} AND code_security_sku_enabled = 0)
          OR (type = 'UnbundledSecurityConfiguration' AND dependabot_delegated_alert_dismissal = #{NOT_SET} AND code_security_sku_enabled = 0)
          OR (type = 'UnbundledSecurityConfiguration' AND secret_protection_sku_enabled IS NULL AND (secret_scanning = #{ENABLED} OR secret_scanning_push_protection = #{ENABLED} OR secret_scanning_validity_checks = #{ENABLED} OR secret_scanning_extended_metadata = #{ENABLED} OR secret_scanning_non_provider_patterns = #{ENABLED} OR secret_scanning_generic_secrets = #{ENABLED} OR secret_scanning_delegated_alert_dismissal = #{ENABLED} OR secret_scanning_delegated_bypass = #{ENABLED}))
          OR (type = 'UnbundledSecurityConfiguration' AND code_security_sku_enabled IS NULL AND (code_scanning = #{ENABLED} OR code_scanning_delegated_alert_dismissal = #{ENABLED}))
        SQL
        columns: %i[
          type
          target_type
          target_id
          name
          secret_scanning
          secret_scanning_push_protection
          secret_scanning_validity_checks
          secret_scanning_extended_metadata
          secret_scanning_non_provider_patterns
          secret_scanning_generic_secrets
          secret_scanning_delegated_alert_dismissal
          secret_scanning_delegated_bypass
          secret_protection_sku_enabled
          code_scanning
          code_scanning_delegated_alert_dismissal
          code_security_sku_enabled
          dependabot_delegated_alert_dismissal
        ],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        log "Processing #{items.size} security configurations (IDs: #{items.keys.first}..#{items.keys.last})"

        items.each do |config_id, attrs|
          config_id = config_id.to_i
          fixes = determine_fixes(attrs)
          next if fixes.empty?

          logger.with_named_tags(log_tags_for(config_id, attrs)) do
            apply_fixes(config_id, attrs, fixes)
          end
        end
      end

      private

      sig { returns(SecurityProductsEnablement::SecurityProductsManager) }
      memoize def services_manager
        SecurityProductsEnablement::SecurityProductsManager.new
      end

      sig { params(config_id: Integer, attrs: T::Hash[Symbol, T.untyped]).returns(T::Hash[String, T.untyped]) }
      def log_tags_for(config_id, attrs)
        tags = { "gh.security_configuration.id" => config_id }

        case attrs[:target_type]
        when "User"
          tags["gh.org.id"] = attrs[:target_id]
        when "Business"
          tags["gh.business.id"] = attrs[:target_id]
        end

        tags
      end

      sig { params(attrs: T::Hash[Symbol, T.untyped]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def determine_fixes(attrs)
        type = attrs[:type]
        extended_metadata = attrs[:secret_scanning_extended_metadata]
        validity_checks = attrs[:secret_scanning_validity_checks]
        secret_protection_sku = attrs[:secret_protection_sku_enabled]
        code_security_sku = attrs[:code_security_sku_enabled]
        dg_delegated = attrs[:dependabot_delegated_alert_dismissal]
        cs_delegated = attrs[:code_scanning_delegated_alert_dismissal]

        fixes = []

        # Fix 1 & Fix 3: secret_scanning_extended_metadata violations
        if services_manager.secret_scanning_extended_metadata_enabled?
          if type == "UnbundledSecurityConfiguration" && extended_metadata == ENABLED && secret_protection_sku == false
            fixes << { field: :secret_scanning_extended_metadata, old_value: "enabled", new_value: "disabled", reason: "secret_protection_sku_enabled is false" }
          elsif validity_checks == DISABLED && extended_metadata == NOT_SET
            fixes << { field: :secret_scanning_extended_metadata, old_value: "not_set", new_value: "disabled", reason: "secret_scanning_validity_checks is disabled" }
          end
        end

        # Fix 2: dependabot_delegated_alert_dismissal enabled with CS SKU nil or false
        if services_manager.dependabot_delegated_alert_dismissal_enabled? &&
            type == "UnbundledSecurityConfiguration" && dg_delegated == ENABLED &&
            (code_security_sku.nil? || code_security_sku == false)
          reason = code_security_sku.nil? ? "code_security_sku_enabled is nil" : "code_security_sku_enabled is false"
          fixes << { field: :dependabot_delegated_alert_dismissal, old_value: "enabled", new_value: "disabled", reason: reason }
        end

        # Fix 5: dependabot_delegated_alert_dismissal not_set with CS SKU false
        if services_manager.dependabot_delegated_alert_dismissal_enabled? &&
            type == "UnbundledSecurityConfiguration" && dg_delegated == NOT_SET && code_security_sku == false
          fixes << { field: :dependabot_delegated_alert_dismissal, old_value: "not_set", new_value: "disabled", reason: "code_security_sku_enabled is false" }
        end

        # Fix 4: code_scanning_delegated_alert_dismissal = not_set with CS SKU = false
        if services_manager.code_scanning_delegated_alert_dismissal_enabled? &&
            type == "UnbundledSecurityConfiguration" && cs_delegated == NOT_SET &&
            code_security_sku == false
          fixes << { field: :code_scanning_delegated_alert_dismissal, old_value: "not_set", new_value: "disabled", reason: "code_security_sku_enabled is false" }
        end

        # Fix 6: SP features enabled with secret_protection_sku_enabled IS NULL
        if type == "UnbundledSecurityConfiguration" && secret_protection_sku.nil?
          SP_FEATURE_COLUMNS.each do |col|
            next unless attrs[col] == ENABLED
            fixes << { field: col, old_value: "enabled", new_value: "not_set", reason: "secret_protection_sku_enabled is nil" }
          end
        end

        # Fix 7: CS features enabled with code_security_sku_enabled IS NULL
        if type == "UnbundledSecurityConfiguration" && code_security_sku.nil?
          CS_FEATURE_COLUMNS.each do |col|
            next unless attrs[col] == ENABLED
            fixes << { field: col, old_value: "enabled", new_value: "not_set", reason: "code_security_sku_enabled is nil" }
          end
        end

        fixes
      end

      sig { params(config_id: Integer, attrs: T::Hash[Symbol, T.untyped], fixes: T::Array[T::Hash[Symbol, T.untyped]]).void }
      def apply_fixes(config_id, attrs, fixes)
        fixes.each do |fix|
          log_message = "#{fix[:field]} #{fix[:old_value]} → #{fix[:new_value]} (#{fix[:reason]})"

          if dry_run?
            log "[DRY RUN] Would update: #{log_message}"
          else
            log "Updating: #{log_message}"
          end
        end

        return if dry_run?

        update_attrs = fixes.each_with_object({}) { |fix, h| h[fix[:field]] = fix[:new_value].to_sym }

        write_to(model_class: SecurityConfig) do
          config = SecurityConfiguration.find(config_id)
          config.update!(update_attrs)
        rescue ActiveRecord::RecordInvalid => e
          log "Failed to update config #{config_id}: #{e.message}. Skipping."
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  args = GitHub::Transitions::Arguments.parse(ARGV)
  GitHub::Transitions::FixSecurityConfigurationsForUnifiedValidator.new(args).run
end
