# typed: false
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    module Search
      class RepositoryView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

        attr_reader :repository
        attr_reader :search_entry

        def initialize(*args)
          super(*args)
          @search_entry = nil

          index = Elastomer::Indexes::Repos.new
          result = index.docs.get(type: "repository", id: repository.id)

          @search_entry = result["_source"] if result["found"]
        end

        def searchable?
          repository.repo_is_searchable?
        end

        def reindex?
          return false unless searchable?
          return true  unless search_entry?
          return true  unless public_match?
          return true  unless up_to_date?
          false
        end

        def reindex_reason
          return "The repository is missing from the search index" unless search_entry?
          return "The public flag has been udpated"                unless public_match?
          return "The repository has been recently updated"        unless up_to_date?
          nil
        end

        def purge?
          !searchable? && search_entry?
        end

        def purge_reason
          return "The repository is un-routed on the file servers"   if repository.route.nil?
          return "The repository owner has been flagged as spammy"   if repository.spammy?
          return "The repository has been disabled"                  if !repository.disabled_at.nil?
          return "The repository does not belong to a valid network" if repository.network.nil?
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
          repository.updated_at == Time.parse(search_entry["updated_at"])
        end
      end
    end
  end
end
