# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

module GitHub
  module Transitions
    class BackfillDeployKeyPolicy < Base
      class PublicKey < ApplicationRecord::Domain::Users
        self.table_name = :public_keys
      end

      class ConfigurationEntries < ApplicationRecord::Domain::ConfigurationEntries
        self.table_name = :configuration_entries
      end

      sig { returns(T.nilable(Integer)) }
      attr_reader :total_process_batch_errors

      sig { returns(T.nilable(Integer)) }
      attr_reader :total_rows_affected

      iterate_over :database_table, params: {
        model_class: PublicKey,
        conditions: "repository_id IS NOT NULL", # Only iterate over public keys that are associated with a repository (aka deploy keys)
        columns: %i[repository_id],
      }

      sig { override.void }
      def after_initialize
        @total_process_batch_errors = T.let(0, T.nilable(Integer))
        @total_rows_affected = T.let(0, T.nilable(Integer))
        @total_rows_looked_at = T.let(0, T.nilable(Integer))
        @business_ids_looked_at = T.let([], T.nilable(T::Array[Integer]))
        @standalone_organization_ids_looked_at = T.let([], T.nilable(T::Array[Integer]))
        @last_repository_id = T.let(nil, T.nilable(Integer))
      end

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        @total_rows_looked_at = T.must(@total_rows_looked_at) + items.size
        log("Processing batch of #{items.size} items")

        business_ids_with_deploy_keys_and_no_policy = []
        standalone_organization_ids_with_deploy_keys_and_no_policy = []
        count_of_businesses_with_deploy_keys_and_policy_set = 0 # Counting businesses that have deploy keys and a policy set, strictly for logging purposes
        count_of_standalone_organizations_with_deploy_keys_and_policy_set = 0 # Counting standalone organizations that have deploy keys and a policy set, strictly for logging purposes
        skipped_deploy_keys_count = 0 # Counting deploy keys that could not be associated with a business or organization, strictly for logging purposes

        repo_ids = items.values.map { |v| v[:repository_id] }.compact.uniq
        repos = Repository.where(id: repo_ids)
        repos.each do |repo|
          if GitHub.enterprise? && !repo.in_organization?
            # for user owned repos in GHES, the enterprise policy applies
            if GitHub.global_business.deploy_key_policy_unset?
              business_ids_with_deploy_keys_and_no_policy << GitHub.global_business.id
            else
              count_of_businesses_with_deploy_keys_and_policy_set += 1
            end
            next
          end

          if repo.business.present? || repo.enterprise_managed_business.present?
            # repos that have deploy keys and belong to EMU users should also be included here
            # (i.e. enable deploy key policy for the business that belongs to the EMU user that owns the repo)
            biz = repo.business || repo.enterprise_managed_business
            if biz&.deploy_key_policy_unset?
              business_ids_with_deploy_keys_and_no_policy << biz.id
            else
              count_of_businesses_with_deploy_keys_and_policy_set += 1
            end
          elsif repo.organization.present?
            org = repo.organization
            if org&.deploy_key_policy_unset?
              standalone_organization_ids_with_deploy_keys_and_no_policy << org.id
            else
              count_of_standalone_organizations_with_deploy_keys_and_policy_set += 1
            end
          else
            skipped_deploy_keys_count += 1
          end
          @last_repository_id = repo.id if @last_repository_id.nil? || repo.id > @last_repository_id
        end
        log("Skipping #{skipped_deploy_keys_count} deploy keys that are not associated with a business or organization")
        log("Skipping #{count_of_businesses_with_deploy_keys_and_policy_set} businesses that have deploy keys and a policy set")
        log("Skipping #{count_of_standalone_organizations_with_deploy_keys_and_policy_set} standalone organizations that have deploy keys and a policy set")

        if dry_run?
          # Need to filter out existing businesses we would have written to the configuration_entries table
          unique_business_ids_with_deploy_keys_and_no_policy = (business_ids_with_deploy_keys_and_no_policy - T.must(@business_ids_looked_at)).uniq
          log("WOULD have found #{unique_business_ids_with_deploy_keys_and_no_policy.size} businesses with deploy keys and no policy")
          unique_standalone_organization_ids_with_deploy_keys_and_no_policy = (standalone_organization_ids_with_deploy_keys_and_no_policy - T.must(@standalone_organization_ids_looked_at)).uniq
          log("WOULD have found #{unique_standalone_organization_ids_with_deploy_keys_and_no_policy.size} standalone organizations with deploy keys and no policy")

          @business_ids_looked_at = T.must(@business_ids_looked_at).concat(unique_business_ids_with_deploy_keys_and_no_policy)
          @standalone_organization_ids_looked_at = T.must(@standalone_organization_ids_looked_at).concat(unique_standalone_organization_ids_with_deploy_keys_and_no_policy)
        else
          unique_business_ids_with_deploy_keys_and_no_policy = business_ids_with_deploy_keys_and_no_policy.uniq
          log("Found #{unique_business_ids_with_deploy_keys_and_no_policy.size} businesses with deploy keys and no policy")
          unique_standalone_organization_ids_with_deploy_keys_and_no_policy = standalone_organization_ids_with_deploy_keys_and_no_policy.uniq
          log("Found #{unique_standalone_organization_ids_with_deploy_keys_and_no_policy.size} standalone organizations with deploy keys and no policy")
        end

        business_configuration_entries = unique_business_ids_with_deploy_keys_and_no_policy.map do |business_id|
          [
            business_id,                                # target_id
            "Business",                                 # target_type
            User.ghost.id,                              # updater_id
            Configurable::DeployKeyPolicy::KEY,         # name
            "true",                                     # value
            1,                                          # final (we set it to true for businesses so that it takes precedence over the org value)
            GitHub::SQL::ArelLiterals::NOW,             # created_at
            GitHub::SQL::ArelLiterals::NOW,             # updated_at
          ]
        end
        standalone_organization_configuration_entries = unique_standalone_organization_ids_with_deploy_keys_and_no_policy.map do |standalone_organization_id|
          [
            standalone_organization_id,                 # target_id
            "User",                                     # target_type (the AR model, AKA User==Organization)
            User.ghost.id,                              # updater_id
            Configurable::DeployKeyPolicy::KEY,         # name
            "true",                                     # value
            0,                                          # final (we set it to false for orgs so that businesses take precedence)
            GitHub::SQL::ArelLiterals::NOW,             # created_at
            GitHub::SQL::ArelLiterals::NOW,             # updated_at
          ]
        end
        all_entries = business_configuration_entries + standalone_organization_configuration_entries
        add_deploy_key_policy_entries(all_entries)
        if dry_run?
          log("Batch complete. #{@total_rows_affected} TOTAL rows WOULD have been affected, #{@total_process_batch_errors} TOTAL batch errors")
        else
          log("Batch complete. #{@total_rows_affected} TOTAL rows affected, #{@total_process_batch_errors} TOTAL batch errors")
        end
        log("Last repository id processed: #{@last_repository_id}")
        log("Total rows looked at so far: #{@total_rows_looked_at}")
      end

      sig { params(entries: T::Array[T.untyped]).void }
      def add_deploy_key_policy_entries(entries)
        if entries.empty?
          log("No entries to write to configuration_entries table")
          return
        end

        if dry_run?
          log("Would write #{entries.size} rows to configuration_entries table")
          @total_rows_affected = T.must(@total_rows_affected) + entries.size
          return
        end

        log("Writing #{entries.size} rows to configuration_entries table")
        write_to(model_class: ConfigurationEntries) do
          begin
            rows_affected = ConfigurationEntries.connection.update(Arel.sql(<<-SQL, rows: Arel::Nodes::ValuesList.new(entries)))
              INSERT INTO `configuration_entries` (target_id, target_type, updater_id, name, value, final, created_at, updated_at)
              :rows
            SQL
          rescue ActiveRecord::RecordNotUnique
            log("Caught ActiveRecord::RecordNotUnique error, skipped the entire batch insert")
            log("Ids we failed to insert configuration entries for: #{entries.map { |entry| entry[0] }.uniq}")
            @total_process_batch_errors = T.must(@total_process_batch_errors) + 1
            return
          end
          log("Wrote #{rows_affected} rows to configuration_entries table")
          @total_rows_affected = T.must(@total_rows_affected) + rows_affected
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
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::BackfillDeployKeyPolicy.new(args).run
end
