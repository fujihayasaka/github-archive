# typed: true
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    module Search
      class CodesearchView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
        class NotImplemented < StandardError; end

        attr_reader :repository
        attr_reader :search_entry
        attr_reader :document_count

        def initialize(attributes = nil)
          # Direct access to the codesearch cluster via Elastomer::Indexes::CodeSearch is only supported when using
          # Elastomer-based code search.

          super(attributes)
          @search_entry = nil

          # TODO: check Rails.env.production? here too if we want to
          # enable Stafftools legacy code search behavior in local dev/CI
          if GitHub.use_elastomer_code_search?
            @index = Elastomer::Indexes::CodeSearch.new
            @search_entry = @index.repository(repository.id)
            @document_count = @index.file_count(repository.id)
          end
        end

        def searchable?
          repository.code_is_searchable?
        end

        def reindex?
          return false unless searchable?
          return true unless GitHub.use_elastomer_code_search?
          return true  unless search_entry?
          return true  unless public_match?
          return true  unless up_to_date?
          false
        end

        def reindex_reason
          if GitHub.use_elastomer_code_search?
            return "The source code is missing from the search index" unless search_entry?
            return "The public flag has been updated"                 unless public_match?
            return "The source code has been recently updated"        unless up_to_date?
          end
          nil
        end

        def purge?
          GitHub.use_elastomer_code_search? && !searchable? && search_entry?
        end

        def purge_reason
          return nil unless GitHub.use_elastomer_code_search?

          return "The repository is un-routed on the file servers"   if repository.route.nil?
          return "The repository owner has been flagged as spammy"   if repository.spammy?
          return "The repository has been disabled"                  if !repository.disabled_at.nil?
          return "The repository does not belong to a valid network" if repository.network.nil?
          return "The repository has no source code"                 if repository.empty?

          if repository.fork?
            return "The repository has no unique commits" if repository.untouched_fork?
            return "The repository has fewer stargazers than the root repository" \
                if !repository.popular_fork?
          end

          nil

        rescue GitHub::DGit::UnroutedError
          "The repository is offline"
        end

        def fork_eligible_for_enabling_code_search?
          return false if !repository.fork?
          return false if repository.code_is_searchable? # already has code search enabled or is popular
          return false if repository.empty?
          return false if repository.untouched_fork? # no unique code to index
          true
        end

        def fork_ineligible_for_enabling_code_search?
          return false if !repository.fork?
          return false if repository.code_is_searchable? # already has code search enabled or is popular
          return false if fork_eligible_for_enabling_code_search? # meets criteria for enabling code search
          true
        end

        # Returns true if the repository has a search entry in the index. Will always be false when using
        # non-Elastomer code search.
        def search_entry?
          !@search_entry.nil?
        end

        def public_match?
          return true unless search_entry?
          repository.public == search_entry["public"]
        end

        def up_to_date?
          return false unless search_entry?
          head_ref = @index.get_metadata["has_code_search_state_docs"] ? search_entry["commit_sha"] : search_entry["head_ref"]

          repository.default_branch == search_entry["head"] &&
          repository.default_oid    == head_ref
        end
      end
    end
  end
end
