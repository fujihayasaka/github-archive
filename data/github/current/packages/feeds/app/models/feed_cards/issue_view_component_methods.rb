# typed: strict
# frozen_string_literal: true

module FeedCards
  module IssueViewComponentMethods
    include GitHub::Memoizer
    include ViewComponentMethods
    extend T::Helpers
    requires_ancestor { ApplicationComponent }
    abstract!

    MAX_BODY_LENGTH = 180
    # This is used in Conduit::Web::Feed to call the batch method `prelude_body_html`.
    # We must call the batch method with the same params we call the method in this component for preloading to work.
    BODY_HTML_CONTEXT = T.let({ context: {} }.freeze, T::Hash[T.untyped, T.untyped])

    private

    sig { returns(T::Boolean) }
    def render?
      issue.present?
    end

    sig { returns(User) }
    def actor
      item.actor
    end

    sig { returns(T.nilable(T.any(Time, ActiveSupport::TimeWithZone))) }
    def timestamp
      item.created_at
    end

    sig { returns(String) }
    def action
      item.action_string
    end

    sig { returns(Issue) }
    def issue
      item.issue
    end

    sig { returns(T.nilable(Repository)) }
    def repository
      issue.repository
    end

    sig { params(click_target: T.any(Symbol, String)).returns(T.untyped) }
    def issue_link_data(click_target:)
      helpers.feed_issue_link_data(
        issue: issue,
        click_target: click_target,
        feed_item: item
      )
    end

    sig { returns(T.nilable(String)) }
    memoize def body_html
      issue.prelude_body_html(BODY_HTML_CONTEXT)
    end

    sig { returns(T::Boolean) }
    def issue_body_truncated?
      issue_body_truncator.remaining.content.present?
    end

    sig { returns(HTMLTruncator) }
    memoize def issue_body_truncator
      HTMLTruncator.new(body_html, MAX_BODY_LENGTH, keep_svg_elements: true, strip_block_elements: false)
    end

    sig { returns(String) }
    memoize def truncated_issue_body_html
      issue_body_truncator.to_html(wrap: false)
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def reaction_count_by_content
      (feed&.reaction_count_by_content_by_issue_id || {}).fetch(item.subject_id, {})
    end

    sig { returns(T::Array[T.untyped]) }
    def viewer_reaction_contents
      (feed&.viewer_reaction_contents_by_issue_id || {}).fetch(item.subject_id, [])
    end

    sig { params(click_target: T.any(Symbol, String)).returns(T.untyped) }
    def hydro_data(click_target:)
      helpers.feed_clicks_hydro_attrs(click_target: click_target, feed_item: item)
    end
  end
end
