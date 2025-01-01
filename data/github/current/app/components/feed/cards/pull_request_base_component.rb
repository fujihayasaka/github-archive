# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class PullRequestBaseComponent < BaseComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
      MAX_BODY_LENGTH = 350
      # This is used in Conduit::Web::Feed to call the batch method `prelude_body_html`.
      # We must call the batch method with the same params we call the method in this component for preloading to work.
      BODY_HTML_CONTEXT = { context: {} }.freeze

      private

      def actor
        item.actor
      end

      memoize def pull_request
        item.subject
      end

      memoize def repository
        pull_request.repository
      end

      memoize def state
        pull_request.state
      end

      memoize def is_draft?
        pull_request.draft?
      end

      def pull_request_link_data(click_target:)
        helpers.feed_pull_request_link_data(
          pull_request: pull_request,
          click_target: click_target,
          feed_item: item
        )
      end

      memoize def body_html
        pull_request.prelude_body_html(BODY_HTML_CONTEXT)
      end

      memoize def truncated_body_html
        body_truncator.to_html(wrap: false)
      end

      memoize def body_truncator
        HTMLTruncator.new(body_html, MAX_BODY_LENGTH, keep_svg_elements: true, strip_block_elements: false)
      end

      def body_truncated?
        body_truncator.remaining.content.present?
      end

      def hydro_data(click_target:)
        helpers.feed_clicks_hydro_attrs(click_target: click_target, feed_item: item)
      end

      def reaction_count_by_content
        (feed&.reaction_count_by_content_by_pr_issue_id || {}).fetch(item.issue_id, {})
      end

      def viewer_reaction_contents
        (feed&.viewer_reaction_contents_by_pr_issue_id || {}).fetch(item.issue_id, [])
      end
    end
  end
end
