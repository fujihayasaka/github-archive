# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class SoaBackfillRepoPushedAt < Base

      class SoaRepository < ApplicationRecord::SecurityOverviewAnalytics
        extend T::Sig # rubocop:todo Sorbet/RedundantExtendTSig
        self.table_name = "soa_repositories"

        # Map repository to id, as data table iterator operates on hardcoded `id` field name
        default_scope -> { from("(select *, repository_id as id from soa_repositories) soa_repositories") }

        # Still need alias as data table iterator validator uses unscoped query
        alias_attribute :id, :repository_id
      end

      iterate_over :database_table, params: {
        model_class: SoaRepository,
        # only update rows that don't already have a value
        conditions: "pushed_at is null",
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        repository_ids = items.keys
        sc_last_push_by_repo = RepositorySecurityCenterConfig
          .where(repository_id: repository_ids)
          .where.not(last_push: nil)
          .pluck(:repository_id, :last_push)
          .to_h

        if dry_run?
          log "Dry run: would update pushed_at for #{sc_last_push_by_repo.length} repositories", sc_last_push_by_repo:
        else
          updated_at = Time.current
          write_to(model_class: SoaRepository) do
            sc_last_push_by_repo.each do |repository_id, pushed_at|
              SoaRepository
                .where(
                  repository_id:,
                  pushed_at: nil, # only update it still null
                )
                .update_all(
                  pushed_at:,
                  updated_at:, # .update_all issues a direct `UPDATE`, so Rails can't set this value for us
                )
              if verbose?
                log "Updated pushed_at for repository", repository_id:, pushed_at:
              end
            end
          end
          log "Updated pushed_at for #{sc_last_push_by_repo.length} repositories", sc_last_push_by_repo:
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

  GitHub::Transitions::SoaBackfillRepoPushedAt.new(args).run
end
