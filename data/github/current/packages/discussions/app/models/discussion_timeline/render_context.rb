# typed: true
# frozen_string_literal: true

class DiscussionTimeline
  # Public: Default implementations of the methods that all "render contexts" need to implement.
  module RenderContext
    extend T::Helpers
    extend T::Sig
    include GitHub::Memoizer

    abstract!

    sig { returns T.any(Discussions::NullShowStats, DiscussionsController::ShowStats) }
    def show_stats
      Discussions::NullShowStats.new
    end

    sig { returns T.nilable(T::Boolean) }
    memoize def blocked_from_commenting?
      repository&.blocked_from_commenting?(user: viewer, commentable: discussion,
        user_can_push: viewer_can_push?)
    end

    # Public: Render the context we should use for conditional access filtering.
    sig { abstract.returns(T.nilable(ConditionalAccess::Web::Filter)) }
    def cap_filter; end

    # Public: The current Discussion, usually loaded from the URL parameters on the current page view.
    sig { abstract.returns(Discussion) }
    def discussion; end

    # Public: The current Repository, usually loaded from the URL parameters on the current page view.
    #
    # Returns a Repository.
    sig { returns T.nilable(Repository) }
    memoize def repository
      discussion.repository
    end

    sig { returns T.nilable(T::Boolean) }
    memoize def viewer_can_push?
      repository&.pushable_by?(viewer)
    end

    # Public: The User viewing the page, or nil for anonymous renders.
    sig { returns T.nilable(User) }
    def viewer
      nil
    end

    # Public: Access all comments that will be rendered on this page and, ideally, no others - omitting spam comments,
    # comments that will be hidden behind "load more" links. These will be grouped into DiscussionComment::ReplyThread
    # objects that organize replies by the parent comments that they are replies to and collect counts and statistics.
    #
    # Returns a Hash<Integer, DiscussionComment::ReplyThread> containing all loaded reply threads keyed by ID of the
    # parent comment of each.
    sig { returns T::Hash[Integer, DiscussionComment::ReplyThread] }
    def reply_threads_by_parent_id
      {}
    end

    # Public: Construct an enumerable sequence of objects to be included in the discussion timeline. See the
    # Discussions::CollapsibleTimelineComponent and Discussions::TimelineItemsComponent view components.
    #
    # Returns an Enumerable<
    #   Array<DiscussionComment | DiscussionEvent> |
    #   DiscussionTimelineHiddenItems |
    #   NEW_MARKER |
    #   UNREAD_MARKER |
    #   TIMELINE_HEADER>.
    sig do
      returns(
        T::Array[T.any(T::Array[T.any(DiscussionComment, DiscussionEvent)], DiscussionTimelineHiddenItems, Symbol)]
      )
    end
    def renderables
      []
    end

    # Public: Return a flattened view of #renderables.
    sig { returns T::Array[T.any(DiscussionComment, DiscussionEvent)] }
    def timeline_items
      []
    end

    # Public: Return the discussion events associated with this discussion.
    sig { returns T::Array[T.any(DiscussionEvent, DiscussionEventGroup)] }
    def events
      []
    end

    # Public: Are the #events we're rendering paginated in this render?
    sig { returns T::Boolean }
    def has_paginated_events?
      false
    end

    # Public: When did the #viewer last view this discussion? Used to identify which timeline items are "new".
    sig { returns T.nilable(ActiveSupport::TimeWithZone) }
    memoize def last_read_at
      discussion.last_read_at_for(viewer: viewer)
    end

    # Public: Return the number of timeline items considered "new". Used for the "jump to [X] new [nouns]" element.
    sig { returns Integer }
    def new_item_count
      0
    end

    # Public: How should we describe items in our "new item" element? Use different language for Q&A and non-Q&A
    # discussions.
    sig { returns String }
    def new_item_noun
      discussion.supports_mark_as_answer? ? "suggested answer" : "comment"
    end

    # Public: Does this render include the Discussion itself? We can optimize our preloading by skipping Discussion-
    # related work when we aren't actually going to render the Discussion at all.
    sig { returns T::Boolean }
    def render_discussion?
      false
    end

    # Public: Should we render the timeline in parallel using voltron?
    sig { returns T::Boolean }
    def render_with_voltron?
      false
    end

    # Public: Should we include events in the timeline items?
    sig { returns T::Boolean }
    def include_events?
      true
    end

    # Public: Should we render placeholder components for reactions, which will then be replaced by interactable ones
    # after page load?
    sig { returns T::Boolean }
    def render_reaction_placeholders?
      false
    end

    sig { abstract.returns(T::Boolean) }
    def will_render_new_marker?; end

    # Public: Return all timeline items associated with the current discussion (comments and events, ordered by
    # increasing created_at timestamp). Memoized.
    sig { returns T::Array[T.any(DiscussionComment, DiscussionEvent, DiscussionEventGroup)] }
    memoize def timeline_items_for_discussion
      reply_threads = reply_threads_by_parent_id.values
      top_level_comments = reply_threads.map(&:parent)

      GitHub::PrefillAssociations.prefill_associations(top_level_comments, :repository,
        available_records: [repository])

      timeline_items = top_level_comments
      timeline_items += discussion.unsorted_filtered_and_grouped_events_for(viewer) if include_events?

      timeline_items.sort_by(&:created_at)
    end
  end
end
