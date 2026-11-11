# typed: strict
# frozen_string_literal: true

module FeedCards
  module PullRequestViewComponentMethods
    include GitHub::Memoizer
    include FeedCards::ViewComponentMethods
    extend T::Helpers
    requires_ancestor { ApplicationComponent }
    abstract!

    MAX_BODY_LENGTH = 350
    # This is used in Conduit::Web::Feed to call the batch method `prelude_body_html`.
    # We must call the batch method with the same params we call the method in this component for preloading to work.
    BODY_HTML_CONTEXT = T.let({ context: {} }.freeze, T::Hash[Symbol, T.untyped])

    private

    sig { returns(User) }
    def actor
      item.actor
    end

    sig { returns(PullRequest) }
    memoize def pull_request
      item.subject
    end

    sig { returns(T.nilable(Repository)) }
    memoize def repository
      pull_request.repository
    end

    sig { returns(T.nilable(Symbol)) }
    memoize def state
      pull_request.state
    end

    sig { returns(T::Boolean) }
    memoize def is_draft?
      pull_request.draft?
    end

    sig { params(click_target: T.untyped).returns(T::Hash[T.untyped, T.untyped]) }
    def pull_request_link_data(click_target:)
      helpers.feed_pull_request_link_data(
        pull_request: pull_request,
        click_target: click_target,
        feed_item: item
      )
    end

    sig { returns(T.nilable(String)) }
    memoize def body_html
      pull_request.prelude_body_html(BODY_HTML_CONTEXT)
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
    def body_truncated?
      body_truncator.remaining.content.present?
    end

    sig { params(click_target: T.untyped).returns(T::Hash[T.untyped, T.untyped]) }
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
