# typed: false
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    module Search
      class CommitsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

        attr_reader :repository
        attr_reader :search_entry
        attr_reader :document_count

        def initialize(*args)
          super(*args)
          @search_entry = nil

          @index = Elastomer::Indexes::Commits.new
          @search_entry = @index.repository(repository.id)
          @document_count = @index.commit_count(repository.id)
        end

        def searchable?
          repository.commits_are_searchable?
        end

        def reindex?
          return false unless searchable?
          return true unless search_entry?
          return true unless public_match?
          return true unless up_to_date?
          false
        end

        def reindex_reason
          return "The commits are missing from the search index" unless search_entry?
          return "The public flag has been updated" unless public_match?
          return "The commits have been recently updated" unless up_to_date?
          nil
        end

        def purge?
          !searchable? && search_entry?
        end

        def purge_reason
          return "The repository is un-routed on the file servers" if repository.route.nil?
          return "The repository owner has been flagged as spammy" if repository.spammy?
          return "The repository has been disabled" if !repository.disabled_at.nil?
          return "The repository does not belong to a valid network" if repository.network.nil?
          return "The repository has no commits" if repository.empty?

          if repository.fork?
            return "The repository has no unique commits" if repository.untouched_fork?
            return "The repository has fewer stargazers than the root repository" if !repository.popular_fork?
          end

          nil
        rescue GitHub::DGit::UnroutedError
          "The repository is offline"
        end

        def search_entry?
          !@search_entry.nil?
        end

        def public_match?
          return true unless search_entry?
          repository.public == search_entry["public"]
        end

        def up_to_date?
          return unless search_entry?
          head_hash = @index.get_metadata["has_commit_state_docs"] ? search_entry["hash"] : search_entry["head_hash"]

          repository.default_branch == search_entry["head_branch"] && repository.default_oid == head_hash
        end
      end
    end
  end
end
