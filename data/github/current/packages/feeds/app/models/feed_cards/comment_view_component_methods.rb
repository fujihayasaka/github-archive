# typed: strict
# frozen_string_literal: true

module FeedCards
  module CommentViewComponentMethods
    include GitHub::Memoizer
    include FeedCards::ViewComponentMethods
    extend T::Helpers
    requires_ancestor { ApplicationComponent }
    abstract!

    MAX_BODY_LENGTH = 350
    # This is used in Conduit::Web::Feed to call the batch method `prelude_body_html`.
    # We must call the batch method with the same params we call the method in this component for preloading to work.
    BODY_HTML_CONTEXT = T.let({ context: {} }.freeze, T::Hash[T.untyped, T.untyped])


    delegate :pull_request, :pull_request_comment, :issue, :issue_comment, to: :item

    private

    sig { returns(User) }
    def actor
      item.actor
    end

    sig { returns(T.untyped) }
    memoize def comment
      item.subject
    end

    sig { returns(Repository) }
    memoize def repository
      issue.repository
    end

    sig { params(click_target: T.untyped).returns(T.untyped) }
    def pull_request_comment_link_data(click_target:)
      helpers.feed_pull_request_comment_link_data(
        pull_request: pull_request,
        comment: pull_request_comment,
        click_target: click_target,
        feed_item: item
      )
    end

    sig { params(click_target: T.untyped).returns(T.untyped) }
    def issue_comment_link_data(click_target:)
      helpers.feed_issue_comment_link_data(
        issue: issue,
        comment: issue_comment,
        click_target: click_target,
        feed_item: item
      )
    end

    sig { returns(T.nilable(String)) }
    memoize def body_html
      comment.prelude_body_html(BODY_HTML_CONTEXT)
    end

    sig { returns(T.nilable(String)) }
    memoize def truncated_body_html
      body_truncator.to_html(wrap: false)
    end

    sig { returns(HTMLTruncator) }
    memoize def body_truncator
      HTMLTruncator.new(body_html, MAX_BODY_LENGTH, keep_svg_elements: true, strip_block_elements: false)
    end

    sig { returns(T::Boolean) }
    memoize def comment_body_truncated?
      body_truncator.remaining.content.present?
    end

    sig { params(click_target: T.untyped).returns(T.untyped) }
    def hydro_data(click_target:)
      helpers.feed_clicks_hydro_attrs(click_target: click_target, feed_item: item)
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def reaction_count_by_content
      (feed&.reaction_count_by_content_by_pr_issue_id || {}).fetch(item.issue_id, {})
    end

    sig { returns(T::Array[T.untyped]) }
    def viewer_reaction_contents
      (feed&.viewer_reaction_contents_by_pr_issue_id || {}).fetch(item.issue_id, [])
    end
  end
end
