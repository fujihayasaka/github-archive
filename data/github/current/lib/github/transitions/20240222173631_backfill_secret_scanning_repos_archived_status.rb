# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillSecretScanningReposArchivedStatus < Base
      class SecretScanningRepository < ApplicationRecord::TokenScanningService
        self.table_name = :secret_scanning_repos
      end

      iterate_over :database_table, params: {
        model_class: SecretScanningRepository,
        columns: [:archived, :lower_confidence_patterns_enabled, :generic_secrets_enabled],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        # On GHES, checking advanced security availability triggers update calls to the database
        # Since read/write is more an issue on non-GHES, we'll always enter write mode for this
        # transition.
        # The write that occurs happens within Business#sync_enterprise_license
        if GitHub.enterprise?
          ActiveRecord::Base.connected_to(role: :writing) do
            internal_process_batch(items)
          end
        else
          internal_process_batch(items)
        end
      end

      sig { params(items: Iterators::Items).void }
      def internal_process_batch(items)
        log "#{dry_run? ? "Would be updating" : "Updating"} secret_scanning_repos from #{items.keys.first} to #{items.keys.last}"

        repo_ids = items.keys
        items_to_update = T.let({}, Iterators::Items)
        ::Repository.where(id: repo_ids).each do |repo|
          repo_id = repo.id
          repo_archived = repo.archived?
          repo_capabilities = SecretScanning::Features::Repo::Capabilities.new(repo)
          lower_confidence_patterns_enabled = repo_capabilities.lower_confidence_patterns?
          generic_secrets_enabled = repo_capabilities.generic_secrets?

          columns = T.must(items[repo_id])
          if columns[:archived] == repo_archived &&
            columns[:lower_confidence_patterns_enabled] == lower_confidence_patterns_enabled &&
            columns[:generic_secrets_enabled] == generic_secrets_enabled
            log "Repository #{repo_id} is already up to date. Skipping."
            next
          end

          log "Updating repository #{repo_id} in secret_scanning_repos with archived=#{repo_archived}, lower_confidence_patterns_enabled=#{lower_confidence_patterns_enabled}, generic_secrets_enabled=#{generic_secrets_enabled}."

          next if dry_run?

          write_to(model_class: SecretScanningRepository) do
            SecretScanningRepository.where(id: repo_id).update_all(
              archived: repo_archived,
              lower_confidence_patterns_enabled: lower_confidence_patterns_enabled,
              generic_secrets_enabled: generic_secrets_enabled
            )
          end
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

  GitHub::Transitions::BackfillSecretScanningReposArchivedStatus.new(args).run
end
