# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    # This mix-in provides some common helper methods for sorting projects.
    module ProjectV2Sorter
      DESCENDING_DIRECTION_VALUE = "DESC"
      RELEVANCE_FIELD_NAME       = :relevance
      TITLE_FIELD_NAME           = :title
      RECENTLY_VIEWED_FIELD_NAME = :recently_viewed

      def self.sort_projects_v2_by_recently_viewed(projects, viewer_id, direction = nil)
        GitHub.dogstats.time("memex.sort_by_recently_viewed.time") do
          GitHub::PrefillAssociations.prefill_batch_method(projects, :last_project_visit_by_viewer, viewer_id)

          last_visits = projects.map { |project| [project.id, project.last_project_visit_by_viewer(viewer_id)] }.to_h
          sorted_projects = projects.sort_by { |p| last_visits[p.id] || Time.at(0) }
          if direction.nil?
            sorted_projects
          else
            direction == "ASC" ? sorted_projects : sorted_projects.reverse
          end
        end
      end

      # Don't expose internals unless we have to.
      private_constant :DESCENDING_DIRECTION_VALUE,
                       :RELEVANCE_FIELD_NAME,
                       :TITLE_FIELD_NAME,
                       :RECENTLY_VIEWED_FIELD_NAME

      # Sorts a list of projects. Returns a wrapped array of projects. Notes:
      # - even though it requires the query as an argument, it is only needed to determine if relevance can be
      #   used as a sort field. That is because without a query there is nothing to judge relevance against.
      # - This method only sorts and does not perform filtering.
      #
      # Arguments:
      # - projects: an array of projects to sort
      # - order_by: a hash with the following symbolized keys: field and direction.  Field is either: "relevance" or
      #             a method/attribute on the project object.  Direction is either "ASC" or "DESC".
      # - query: passed in query that was used to filter the projects.
      def sort_projects_v2(projects, order_by, query, viewer)
        return [] if projects.nil?

        field_sym = order_by[:field].to_sym

        sorted =
          if field_sym == RELEVANCE_FIELD_NAME && query.present?
            projects.compact.sort_by { |p| GitHub::Levenshtein.similarity(p.title, query) }
          elsif field_sym == RELEVANCE_FIELD_NAME
            projects.compact.sort_by { |p| p.updated_at }
          elsif field_sym == RECENTLY_VIEWED_FIELD_NAME
            ProjectV2Sorter.sort_projects_v2_by_recently_viewed(projects, viewer.id)
          elsif field_sym == TITLE_FIELD_NAME
            projects.compact.sort_by { |p| p[:title].to_s.downcase }
          else
            projects.compact.sort_by { |p| p.send(field_sym) || "" }
          end

        sorted = order_by[:direction] == DESCENDING_DIRECTION_VALUE ? sorted.reverse : sorted

        ArrayWrapper.new(sorted)
      end
    end
  end
end
