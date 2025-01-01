# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillSecurityConfigurationsForDelegatedBypassEnabledRepos < Base
      include GitHub::Memoizer

      CONFIG_KEY_USER_ENABLED = "secret_scanning.delegated_bypass.user_enabled"

      # Since we're iterating org by org, we can have a more aggressive repo batch size,
      # since it's less likely that *every* batch of repos would be large.
      DEFAULT_REPO_BATCH_SIZE = T.let(GitHub.enterprise? ? 10000 : 5000, Integer)

      # Default number of rows to process at a time.
      DEFAULT_PROCESS_BATCH_SIZE = T.let(
        GitHub.enterprise? ? 1000 : 100, Integer
      )

      sig { returns(Integer) }
      def repo_batch_size
        return arguments[:repo_batch_size].to_i if arguments[:repo_batch_size].present?
        DEFAULT_REPO_BATCH_SIZE
      end

      # Returns the number of rows to process at a time
      sig { returns(Integer) }
      def process_batch_size
        arguments[:process_batch_size] || DEFAULT_PROCESS_BATCH_SIZE
      end

      class SecretScanningBypassReviewer < ApplicationRecord::Domain::TokenScanningService
        self.table_name = :secret_scanning_bypass_reviewers
      end

      class OwnerScope < ApplicationRecord::Domain::TokenScanningService
        self.table_name = :owner_scopes
      end

      class ConfigurationEntry < ApplicationRecord::Domain::ConfigurationEntries
        self.table_name = "configuration_entries"
      end

      class SecurityConfigurationTable < ApplicationRecord::Notify
        self.table_name = "security_configurations"
      end

      sig { returns(Integer) }
      memoize def ghost_id
        User.ghost&.id || 0
      end

      # Iterate over all organizations with delegated bypass enabled.
      # Organizations are implemented as Users, under the hood.
      iterate_over :database_table, params: {
        model_class: ConfigurationEntry,
        conditions: "name = '#{CONFIG_KEY_USER_ENABLED}' AND target_type = 'User' AND value = 'true'",
        columns: %i[target_id],
      }

      sig { override.void }
      def after_initialize
        grc = SecurityConfigurationTable.where(target_type: "global", target_id: 0).first
        @grc_id = T.let(grc.nil? ? nil : grc.id, T.nilable(Integer))
      end

      # This transition iterates over all organizations with delegated bypass enabled,
      # and identifies the repositories with non-GRC (GitHub Recommended Configuration) security configurations.
      # It then enables delegated bypass for those security configurations, and creates bypass reviewers for them.
      #
      # It handles 1 org at a time.
      #
      # Relies on the default `start_id` and `end_id` arguments for iterating over ConfigurationEntry.
      #
      # Uses a custom `repo_batch_size` argument to control the batch size for iterating over repositories.
      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        items.each do |config_entry_id, value|
          org_id = T.let(value[:target_id], Integer)
          log "Starting to process config_entry_id=#{config_entry_id}, org_id=#{org_id}"
          bypass_reviewers_for_org = SecretScanningBypassReviewer.joins("INNER JOIN owner_scopes on secret_scanning_bypass_reviewers.owner_scope_id = owner_scopes.id")
          .where("owner_scopes.owner_id": org_id, "owner_scopes.owner_scope": "ORG")
          .select("secret_scanning_bypass_reviewers.*")
          .to_a
          process_security_configs_for_org(org_id, bypass_reviewers_for_org)
          log "Completed processing config_entry_id=#{config_entry_id}, org_id=#{org_id}"
        end
      end

      private

      sig { params(security_config_ids_with_pp_setting: T::Hash[Integer, Integer], bypass_reviewers_for_org: T::Array[T.untyped], org_id: Integer).void }
      def update_security_configs_and_bypass_reviewers(security_config_ids_with_pp_setting, bypass_reviewers_for_org, org_id)
        security_config_ids_pp_enabled = []
        security_config_ids_pp_not_set = []
        security_config_ids_pp_disabled = []

        security_config_ids_with_pp_setting.each do |security_config_id, pp_setting|
          if pp_setting == 1
            security_config_ids_pp_enabled << security_config_id
          elsif pp_setting == 2
            security_config_ids_pp_not_set << security_config_id
          else
            security_config_ids_pp_disabled << security_config_id
          end
        end

        # For the non-GRC security configurations, set delegated bypass to the same value as push protection
        if dry_run?
          log "Would have set delegated bypass for security configurations. enabled_count=#{security_config_ids_pp_enabled.count}, disabled_count=#{security_config_ids_pp_disabled.count}, not_set_count=#{security_config_ids_pp_not_set.count}"
        else
          write_to(model_class: SecurityConfiguration) do
            SecurityConfigurationTable.where(id: security_config_ids_pp_enabled).update_all(secret_scanning_delegated_bypass: 1)
            SecurityConfigurationTable.where(id: security_config_ids_pp_disabled).update_all(secret_scanning_delegated_bypass: 0)
            SecurityConfigurationTable.where(id: security_config_ids_pp_not_set).update_all(secret_scanning_delegated_bypass: 2)
          end
        end

        # Create bypass reviewers for each non-GRC security configuration that has push protection enabled or not set
        bypass_reviewer_rows = []
        (security_config_ids_pp_enabled + security_config_ids_pp_not_set).each do |security_configuration_id|
          bypass_reviewers_for_org.each do |bypass_reviewer|
            bypass_reviewer_rows.push(
              {
                reviewer_id: bypass_reviewer.reviewer_id,
                reviewer_type: bypass_reviewer.reviewer_type,
                owner_scope_id: bypass_reviewer.owner_scope_id,
                security_configuration_id: security_configuration_id,
              }
            )
          end
        end

        bypass_reviewers_created_count = 0
        existing_bypass_reviewers_count = 0

        bypass_reviewer_rows.each do |bypass_reviewer_row|
          if SecretScanningBypassReviewer.exists?(bypass_reviewer_row)
            existing_bypass_reviewers_count += 1
          else
            if !dry_run?
              write_to(model_class: SecretScanningBypassReviewer) do
                SecretScanningBypassReviewer.insert(bypass_reviewer_row)
              end
              bypass_reviewers_created_count += 1
            end
          end
        end
        log "#{dry_run? ? "would have " : ""} created #{bypass_reviewers_created_count} bypass reviewers for org_id=#{org_id}, existing_bypass_reviewers_count=#{existing_bypass_reviewers_count}"
      end

      sig { params(org_id: Integer).returns(GitHub::QueryBatching::IteratorBuilder[T::Array[Integer]]) }
      def repo_iterator_for_org(org_id)
        # Returns an iterator that yields repository ids for the given org_id, using `repo_batch_size` as the batch size.
        GitHub::QueryBatching::IteratorBuilder.new(batch_size: repo_batch_size) do |iteration|
          bindings = iteration.cursor.arel_bindings
          bindings[:org_id] = org_id

          results = ApplicationRecord::Domain::Repositories.connection.select_rows(Arel.sql(<<-SQL, **bindings))
          SELECT repositories.id
          FROM repositories
          WHERE repositories.id >= :lower_id
          AND repositories.owner_id = :org_id
          ORDER BY repositories.id
          LIMIT :limit
        SQL

          iteration << results
        end
      end

      sig { params(org_id: Integer, bypass_reviewers_for_org: T::Array[T.untyped]).void }
      def process_security_configs_for_org(org_id, bypass_reviewers_for_org)
        repo_iterator_for_org(org_id).batches.each do |rows|
          repo_ids = rows.flatten
          log "Beginning to process a batch of repos for org_id=#{org_id}. start_repo_id=#{repo_ids.first}"
          repo_configs = RepositorySecurityConfiguration.where(repository_id: repo_ids)

          # The GRC doesn't exist on enterprise, so in that case, all repos with security configurations are non-GRC
          other_repo_configs = repo_configs
          if @grc_id
            _, other_repo_configs = repo_configs.partition { |repo_config| repo_config.security_configuration_id == @grc_id }
          end

          security_config_ids = other_repo_configs.pluck(:security_configuration_id).uniq
          security_config_ids_with_pp_setting = SecurityConfigurationTable.where(id: security_config_ids).pluck(:id, :secret_scanning_push_protection).to_h

          update_security_configs_and_bypass_reviewers(security_config_ids_with_pp_setting, bypass_reviewers_for_org, org_id)
        end

        # If any security configurations for the org still have null values for the delegated bypass column, it's because they have
        # no repos attached. We still need to update them though, using the same logic.
        security_configs_with_pp_setting_no_repos = SecurityConfigurationTable.where(target_type: "User", target_id: org_id, secret_scanning_delegated_bypass: nil).pluck(:id, :secret_scanning_push_protection).to_h
        update_security_configs_and_bypass_reviewers(security_configs_with_pp_setting_no_repos, bypass_reviewers_for_org, org_id)

      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV, additional_arguments: %w(repo_batch_size))

  GitHub::Transitions::BackfillSecurityConfigurationsForDelegatedBypassEnabledRepos.new(args).run
end
