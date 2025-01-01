# typed: false
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    module Search
      class WikiView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

        attr_reader :repository
        attr_reader :search_entry

        def initialize(*args)
          super(*args)
          @search_entry = nil

          index = Elastomer::Indexes::Wikis.new

          if index.get_metadata["has_wiki_state_docs"]
            result = index.docs.get(type: "page", id: repository.id, routing: repository.id)
          else
            result = index.docs.get(type: "wiki", id: repository.id, routing: repository.id)
          end

          @search_entry = result["_source"] if result["found"]
        end

        def wiki
          repository.unsullied_wiki
        end

        def searchable?
          repository.wiki_is_searchable?
        end

        def reindex?
          return false unless searchable?
          return true  unless search_entry?
          return true  unless public_match?
          return true  unless up_to_date?
          false
        end

        def reindex_reason
          return "The wiki is missing from the search index" unless search_entry?
          return "The public flag has been updated"          unless public_match?
          return "The wiki has been recently updated"        unless up_to_date?
          nil
        end

        def purge?
          !searchable? && search_entry?
        end

        def purge_reason
          return "The wiki does not exist on disk"             if wiki.exist?
          return "The wiki owner has been flagged as spammy"   if repository.spammy?
          return "The wiki has been disabled"                  if !RepositoryWiki.find_by(repository:).present?
          nil
        rescue GitHub::DGit::UnroutedError
          "The wiki is offline"
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
          wiki.default_oid == search_entry["revision"]
        end
      end
    end
  end
end
