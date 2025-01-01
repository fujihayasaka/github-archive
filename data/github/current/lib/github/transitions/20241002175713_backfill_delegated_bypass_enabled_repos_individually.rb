# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillDelegatedBypassEnabledReposIndividually < Base
      include GitHub::Memoizer

      CONFIG_KEY_USER_ENABLED = "secret_scanning.delegated_bypass.user_enabled"

      # Since we're iterating org by org, we can have a more aggressive repo batch size,
      # since it's less likely that *every* batch of repos would be large.
      DEFAULT_REPO_BATCH_SIZE = T.let(GitHub.enterprise? ? 10000 : 100, Integer)

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
      # and identifies the repositories that need delegated bypass enabled at the repository level.
      # Those are:
      # - Repos with the GitHub Recommended Configuration (GRC), because delegated bypass is not
      # enabled as part of the GRC.
      # - Repos with no security configuration.
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
          # The global org settings would have been saved with a nil security_configuration_id
          .where("owner_scopes.owner_id": org_id, "owner_scopes.owner_scope": "ORG", "security_configuration_id": nil)
          .select("secret_scanning_bypass_reviewers.*")
          .to_a
          process_repos_for_org(org_id, bypass_reviewers_for_org)
          log "Completed processing config_entry_id=#{config_entry_id}, org_id=#{org_id}"
        end
      end

      private

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

      sig { params(bypass_reviewers_for_org: T::Array[T.untyped], repo_ids: T::Array[Integer]).void }
      def enable_delegated_bypass_individually_for_repos(bypass_reviewers_for_org, repo_ids)
        # Create repo-level owner scopes, if they don't already exist
        repo_owner_scope_rows = repo_ids.map do |repo_id|
          {
            owner_id: repo_id,
            owner_scope: "REPO"
          }
        end

        owner_scopes_created_count = 0
        existing_owner_scopes_count = 0
        repo_owner_scope_rows.each do |owner_scope|
          if OwnerScope.exists?(owner_scope)
            existing_owner_scopes_count += 1
          else
            if !dry_run?
              write_to(model_class: OwnerScope) do
                OwnerScope.insert(owner_scope)
              end
            end
            owner_scopes_created_count += 1
          end
        end
        log "#{dry_run? ? "would have " : ""} created #{owner_scopes_created_count} repo-level owner scopes. #{existing_owner_scopes_count} existing owner scopes."

        repo_ids_to_owner_scope_ids = OwnerScope.where(owner_scope: "REPO", owner_id: repo_ids).pluck(:owner_id, :id).to_h

        # Create bypass reviewers
        bypass_reviewer_rows = []

        repo_ids.each do |repo_id|
          owner_scope_id = repo_ids_to_owner_scope_ids[repo_id]
          if owner_scope_id.nil?
            log "Skipping creating bypass reviewers for repo_id=#{repo_id} because it doesn't have an owner_scope_id"
            next
          end
          bypass_reviewers_for_org.each do |bypass_reviewer|
            bypass_reviewer_rows.push({
              owner_scope_id: owner_scope_id,
              reviewer_id: bypass_reviewer.reviewer_id,
              reviewer_type: bypass_reviewer.reviewer_type,
              security_configuration_id: 0,
            })
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
            end
            bypass_reviewers_created_count += 1
          end
        end

        log "#{dry_run? ? "would have " : ""} created bypass reviewers: #{bypass_reviewers_created_count}, existing bypass reviewers: #{existing_bypass_reviewers_count}"

        # Enable delegated bypass at the repo scope
        config_entry_rows = repo_ids.map do |repo_id|
          {
            target_type: "Repository",
            target_id: repo_id,
            name: CONFIG_KEY_USER_ENABLED,
            value: "true",
            updater_id: ghost_id,
          }
        end

        created = 0
        updated = 0
        if dry_run?
          log "Would have created or updated #{config_entry_rows.size} configuration entries"
        else
          config_entry_rows.each do |config_entry_row|
            existing_config_entry = ConfigurationEntry.where(target_id: config_entry_row[:target_id], target_type: config_entry_row[:target_type], name: config_entry_row[:name]).first
            write_to(model_class: ConfigurationEntry) do
              if existing_config_entry
                begin
                  ConfigurationEntry.update(existing_config_entry.id, value: "true")
                rescue ActiveRecord::RecordNotUnique
                  ConfigurationEntry.insert(config_entry_row)
                  created += 1
                else
                  updated += 1
                end
              else
                ConfigurationEntry.insert(config_entry_row)
                created += 1
              end
            end
          end
          log "Created #{created} configuration entries and updated #{updated}"
        end
      end

      sig { params(org_id: Integer, bypass_reviewers_for_org: T::Array[T.untyped]).void }
      def process_repos_for_org(org_id, bypass_reviewers_for_org)
        repo_iterator_for_org(org_id).batches.each do |rows|
          repo_ids = rows.flatten
          log "Beginning to process a batch of repos for org_id=#{org_id}. start_repo_id=#{repo_ids.first}"
          repo_configs = RepositorySecurityConfiguration.where(repository_id: repo_ids)
          repo_ids_with_configs = repo_configs.pluck(:repository_id)
          grc_repo_configs = []
          # The GRC doesn't exist on enterprise, so in that case, all repos with security configurations are non-GRC.
          if @grc_id
            grc_repo_configs, _ = repo_configs.partition { |repo_config| repo_config.security_configuration_id == @grc_id }
          end

          repo_ids_without_configs = repo_ids - repo_ids_with_configs
          grc_repo_ids = grc_repo_configs.pluck(:repository_id)

          enable_delegated_bypass_individually_for_repos(bypass_reviewers_for_org, repo_ids_without_configs + grc_repo_ids)
          log "Completed processing a batch of repos for org_id=#{org_id}. start_repo_id=#{repo_ids.first}"
        end
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

  GitHub::Transitions::BackfillDelegatedBypassEnabledReposIndividually.new(args).run
end
