# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class LatestAnsweredDiscussionEvent < Platform::Loader
      def self.load(discussion)
        self.for.load(discussion)
      end

      def fetch(discussions)
        # Don't check .answered? because that attempts to actually load the comment and category. In this context, we
        # only care if the field is populated so that the query is valid.
        answered_discussions = discussions.select { |discussion| discussion.chosen_comment_id.present? }
        return {} if answered_discussions.empty?

        discussions_by_id = answered_discussions.index_by(&:id)
        events = DiscussionEvent.find_by_sql(build_multi_query(answered_discussions))
        events.each_with_object({}) do |event, results|
          discussion = discussions_by_id[event.discussion_id]
          results[discussion] = event
        end
      end

      private

      ANSWERED_TYPE = DiscussionEvent.event_types["answer_marked"]

      def build_multi_query(discussions)
        params = {
          discussion_ids: discussions.map(&:id),
          chosen_comment_ids: discussions.map(&:chosen_comment_id),
          answered_type: ANSWERED_TYPE,
        }

        # Use a self-join to find the maximum created_at answer_marked events associated with each discussion ID.
        Arel.sql(<<~SQL, **params)
          SELECT
            discussion_events.id,
            discussion_events.repository_id,
            discussion_events.discussion_id,
            discussion_events.actor_id,
            discussion_events.comment_id,
            discussion_events.event_type,
            discussion_events.created_at
          FROM (
            SELECT
              discussion_id,
              MAX(id) AS max_id
            FROM discussion_events
            WHERE discussion_id IN (:discussion_ids) AND event_type = :answered_type AND comment_id IN (:chosen_comment_ids)
            GROUP BY discussion_id
          ) AS each_max
          INNER JOIN discussion_events
          ON discussion_events.id = each_max.max_id
        SQL
      end

    end
  end
end
