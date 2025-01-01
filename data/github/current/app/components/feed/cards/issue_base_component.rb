# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class IssueBaseComponent < BaseComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
      MAX_BODY_LENGTH = 180
      # This is used in Conduit::Web::Feed to call the batch method `prelude_body_html`.
      # We must call the batch method with the same params we call the method in this component for preloading to work.
      BODY_HTML_CONTEXT = { context: {} }.freeze

      private

      def render?
        issue.present? && user_feature_enabled?(:feeds_v2)
      end

      def actor
        item.actor
      end

      def timestamp
        item.created_at
      end

      def action
        item.action_string
      end

      def issue
        item.issue
      end

      def repository
        issue.repository
      end

      def issue_link_data(click_target:)
        helpers.feed_issue_link_data(
          issue: issue,
          click_target: click_target,
          feed_item: item
        )
      end

      memoize def body_html
        issue.prelude_body_html(BODY_HTML_CONTEXT)
      end

      def issue_body_truncated?
        issue_body_truncator.remaining.content.present?
      end

      memoize def issue_body_truncator
        HTMLTruncator.new(body_html, MAX_BODY_LENGTH, keep_svg_elements: true, strip_block_elements: false)
      end

      memoize def truncated_issue_body_html
        issue_body_truncator.to_html(wrap: false)
      end

      def reaction_count_by_content
        (feed&.reaction_count_by_content_by_issue_id || {}).fetch(item.subject_id, {})
      end

      def viewer_reaction_contents
        (feed&.viewer_reaction_contents_by_issue_id || {}).fetch(item.subject_id, [])
      end

      def hydro_data(click_target:)
        helpers.feed_clicks_hydro_attrs(click_target: click_target, feed_item: item)
      end
    end
  end
end
