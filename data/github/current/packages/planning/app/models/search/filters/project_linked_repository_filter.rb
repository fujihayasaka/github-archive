# typed: true
# frozen_string_literal: true

module Search
  module Filters
    # The ReviewRequestFilter is used to limit search results to projects that
    # are linked to a specified repository.
    # This class encapsulates the logic of looking up the repository and generating ElasticSearch term filters.
    class ProjectLinkedRepositoryFilter < TermFilter
      def initialize(opts = {})
        super(opts)

        @current_user = options.fetch(:current_user, nil)

        map_bool_collection
      end

      def build(values)
        return if values.blank?

        repo = Repository.with_name_with_owner(values.first)

        repo_id = if repo&.readable_by?(@current_user)
          repo.id
        else
          # Return no results if the repo isn't found or isn't readable by the
          # current user.
          0
        end

        build_term_filter(:linked_repository_ids, [repo_id], execution: execution)
      end
    end
  end
end
