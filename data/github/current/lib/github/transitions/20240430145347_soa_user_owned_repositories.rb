# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

module GitHub
  module Transitions
    class SoaUserOwnedRepositories < Base
      BATCH_SIZE = 1000

      class SoaRepository < ApplicationRecord::SecurityOverviewAnalytics
        self.table_name = "soa_repositories"

        # Map repository to id, as data table iterator operates on hardcoded `id` field name
        default_scope -> { from("(select *, repository_id as id from soa_repositories) soa_repositories") }

        # Still need alias as data table iterator validator uses unscoped query
        alias_attribute :id, :repository_id
      end

      iterate_over :database_table, params: {
        model_class: SoaRepository,
        # Querying by default value of owner_id column
        conditions: "owner_id = 0",
        columns: %i[owner_id owner_type business_id updated_at],
      }

      sig { override.void }
      def after_initialize
        @total_records_updated = T.let(0, T.nilable(Integer))
        @total_records_skipped = T.let(0, T.nilable(Integer))
        @total_records_missing_repository = T.let(0, T.nilable(Integer))
        @total_records_missing_owner = T.let(0, T.nilable(Integer))
        @total_records_non_emu_user_repos = T.let(0, T.nilable(Integer))
      end

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        log "#{dry_run? ? "Would be updating" : "Updating"} soa_repositories from #{items.keys.first} to #{items.keys.last}"

        items.each_pair do |key, values|
          repository_id = key
          owner_id = values[:owner_id]
          owner_type = values[:owner_type]
          business_id = values[:business_id]
          updated_at = values[:updated_at]

          repo = Repository.find_by(id: repository_id)

          if repo.nil?
            log "Repository with repository_id = #{repository_id} not found"
            @total_records_missing_repository = T.must(@total_records_missing_repository) + 1
            next
          end

          owner = repo.owner

          if owner.nil?
            log "Owner not found for repository_id = #{repository_id}"
            @total_records_missing_owner = T.must(@total_records_skipped) + 1
            next
          end

          new_owner_id = owner.id

          if owner.organization?
            new_business_id = owner.business&.id # This can be nil for stand-alone orgs
            new_owner_type = "ORGANIZATION"
          elsif owner.user?
            if owner.is_enterprise_managed?
              new_business_id = owner.enterprise_managed_business&.id
              new_owner_type = "USER"
            elsif GitHub.enterprise?
              new_business_id = GitHub.global_business.id
              new_owner_type = "USER"
            end
          end

          if new_owner_type.nil?
            log "Owner is not in scope for repository_id = #{repository_id}"
            @total_records_non_emu_user_repos = T.must(@total_records_non_emu_user_repos) + 1
            next
          end

          if owner_id == new_owner_id && owner_type == new_owner_type && business_id == new_business_id
            log "Owner and business id are already up to date for repository_id = #{repository_id}"
            @total_records_skipped = T.must(@total_records_skipped) + 1
            next
          end

          log "Updating owner and business id in soa_repositories for \
           repository_id = #{repository_id}, old values (\
           owner_id = #{owner_id}, \
           owner_type = #{owner_type}
           business_id = #{business_id}, \
           updated_at #{updated_at}), new values (\
            owner_id = #{new_owner_id}, \
            owner_type = #{new_owner_type}, \
            business_id = #{new_business_id})"

          @total_records_updated = T.must(@total_records_updated) + 1

          next if dry_run?

          write_to(model_class: SoaRepository) do
            SoaRepository
              .where(repository_id: repository_id)
              .update(
                owner_id: new_owner_id,
                owner_type: new_owner_type,
                business_id: new_business_id
              )
          end
        end

        log("#{dry_run? ? "Would have updated" : "Updated"} #{@total_records_updated} records")
        log("#{dry_run? ? "Would have skipped" : "Skipped"} #{@total_records_skipped} records")
        log("#{dry_run? ? "Would have skipped" : "Skipped"} #{@total_records_missing_repository} records due to missing repository")
        log("#{dry_run? ? "Would have skipped" : "Skipped"} #{@total_records_missing_owner} records due to missing owner")
        log("#{dry_run? ? "Would have skipped" : "Skipped"} #{@total_records_non_emu_user_repos} records due to non-EMU user repos")
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

  GitHub::Transitions::SoaUserOwnedRepositories.new(args).run
end
