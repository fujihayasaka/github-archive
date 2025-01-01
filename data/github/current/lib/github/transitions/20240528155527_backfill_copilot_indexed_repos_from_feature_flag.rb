# typed: true
# frozen_string_literal: true

# This migration is part of the removal of the `blackbird_enable_code_embedding`
# and `blackbird_enable_markdown_embedding` feature flags. It ensures that any
# Repository for which either of these feature flags is set has a corresponding
# entry in the CopilotIndexedRepositories table.

require "#{Rails.root}/config/environment"

module GitHub
  module Transitions
    class BackfillCopilotIndexedReposFromFeatureFlag < GitHub::Transitions::Base
      BATCH_SIZE = 100

      def perform
        log "Starting transition with a batch size of #{BATCH_SIZE}"
        @repos_to_process.each_slice(BATCH_SIZE) do |repo_batch|
          to_create = []
          repos = Repository.where(id: repo_batch)
          repos.map do |repo|
            needs_code = repo.feature_enabled? :blackbird_enable_code_embedding
            needs_markdown = repo.feature_enabled? :blackbird_enable_markdown_embedding
            if needs_code || needs_markdown
              to_create << { repository_id: repo.id, organization_id: repo.owner_id, markdown_only: needs_markdown && !needs_code }
            end
          end
          log "(dry_run: #{dry_run?}) Creating #{to_create.size} CopilotIndexedRepositories." if verbose?

          write_to(model_class: CopilotIndexedRepositories) do
            CopilotIndexedRepositories.upsert_all(to_create) # rubocop:disable GitHub/UpsertAll
          end unless dry_run?
        end
      end

      def after_initialize
        ActiveRecord::Base.connected_to(role: :reading) do
          markdown_feature_flag = FlipperFeature.find_by(name: :blackbird_enable_markdown_embedding)
          code_feature_flag = FlipperFeature.find_by(name: :blackbird_enable_code_embedding)

          if !markdown_feature_flag.present?
            log "Could not find markdown feature flag"
            return
          end

          if !code_feature_flag.present?
            log "Could not find code feature flag"
            return
          end

          @repos_to_process = markdown_feature_flag.actor_ids_by_class.to_h.values + code_feature_flag.actor_ids_by_class.to_h.values
          @repos_to_process.flatten!
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
  GitHub::Transitions::BackfillCopilotIndexedReposFromFeatureFlag.new(args).run
end
