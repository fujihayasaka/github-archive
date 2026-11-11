# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class PopulateSecretScanningReposWikiScanning < Base
      class RepositoryWiki < ApplicationRecord::Domain::Repositories
        self.table_name = :repository_wikis
      end

      class SecretScanningRepos < ApplicationRecord::Domain::TokenScanningService
        self.table_name = :secret_scanning_repos
      end

      iterate_over :database_table, params: {
        model_class: RepositoryWiki,
        columns: %i[repository_id],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        wiki_repo_ids = items.values.map { |wiki| wiki[:repository_id] }
        scannable_repos_with_wiki = SecretScanningRepos.where(id: wiki_repo_ids, scannable: true)
        non_scannable_repos_with_wiki = SecretScanningRepos.where(id: wiki_repo_ids, scannable: false)
        if dry_run?
          log("Would be updating #{scannable_repos_with_wiki.count} repos to enable wiki_scanning")
          log("Would be updating #{non_scannable_repos_with_wiki.count} repos to disable wiki_scanning")
        else
          write_to(model_class: SecretScanningRepos) do
            scannable_repos_with_wiki.update_all(wiki_scanning: true)
            non_scannable_repos_with_wiki.update_all(wiki_scanning: false)
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

  GitHub::Transitions::PopulateSecretScanningReposWikiScanning.new(args).run
end
