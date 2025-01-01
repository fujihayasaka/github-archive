# typed: true
# frozen_string_literal: true

class DiscussionComment
  class ReplyThread
    extend T::Sig

    sig do
      params(
        discussion: T.untyped,
        viewer: T.untyped,
        last_read_at: T.untyped,
        items_per_page: T.untyped,
        initial_count: T.untyped
      ).returns(T.untyped)
    end
    def self.all_from_discussion(
      discussion,
      viewer:,
      last_read_at:,
      items_per_page: nil,
      initial_count: DiscussionTimeline::DEFAULT_INITIAL_REPLY_COUNT
    )
      self.record_time(:all_from_discussion_alt) do
        comments_placeholder_pairs = DiscussionTimeline::BatchedDiscussionComment.load(
          discussion,
          viewer,
          initial_count: initial_count,
          items_per_page: items_per_page,
          last_read_at: last_read_at,
        )

        threads_by_parent_id = {}
        comments_placeholder_pairs.each do |comment, placeholder|
          comment.discussion = discussion
          comment.repository = discussion.repository

          if comment.top_level_comment?
            thread = new(comment)
            thread.older_count = placeholder.older_count
            thread.newer_count = placeholder.newer_count
            threads_by_parent_id[comment.id] = thread
          else
            thread = threads_by_parent_id[comment.parent_comment_id]
            thread.replies << comment if thread
          end
        end
        threads_by_parent_id
      end
    end

    sig do
      params(
        parent: T.untyped,
        viewer: T.untyped,
        anchor_id: T.untyped,
        older: T.untyped,
        newer: T.untyped,
        initial_count: T.untyped
      ).returns(T.untyped)
    end
    def self.for_parent_comment(
      parent,
      viewer:,
      anchor_id: nil,
      older: 0,
      newer: 0,
      initial_count: DiscussionTimeline::DEFAULT_INITIAL_REPLY_COUNT
    )
      return new(parent) if anchor_id.nil?

      ids = DiscussionComment.
        filter_spam_for(viewer).
        where(discussion_id: parent.discussion_id).
        where(parent_comment_id: parent.id).
        order(id: :asc).
        pluck(:id)

      anchor_index = ids.index(anchor_id.to_i) || 0
      older_index_end = (anchor_index - older).clamp(0, ids.size)
      older_count = older_index_end
      newer_index_start = (anchor_index + initial_count + newer).clamp(0, ids.size)
      newer_count = ids.slice(newer_index_start, ids.size).size
      selected_ids = ids.slice(older_index_end...newer_index_start)
      replies = DiscussionComment.where(id: selected_ids).order(id: :asc)
      new(parent, replies.to_a).tap do |thread|
        thread.older_count = older_count
        thread.newer_count = newer_count
      end
    end

    sig { params(method_name: T.untyped).returns(T.untyped) }
    def self.record_time(method_name)
      start_time = GitHub::Dogstats.monotonic_time
      yield
    ensure
      elapsed = GitHub::Dogstats.duration(start_time)
      GitHub.dogstats.distribution("discussion_timeline.reply_thread.dist", elapsed, tags: ["method:#{method_name}"])
    end

    sig { params(parent: T.untyped, replies: T.untyped).void }
    def initialize(parent, replies = [])
      @parent = parent
      @replies = replies
      @older_count = 0
      @newer_count = 0
    end

    attr_reader :parent, :replies
    attr_accessor :older_count, :newer_count

    sig { returns(T.untyped) }
    def has_older_replies?
      @older_count > 0
    end

    sig { returns(T.untyped) }
    def has_newer_replies?
      @newer_count > 0
    end

    # Public: Compute the number of replies in this thread (rendered or not) that are newer than a last_read_at
    # timestamp.
    #
    # last_read_at - An ActiveSupport::TimeWithZone or nil. Assumption: this is the same :last_read_at parameter
    #  that was originally supplied to `.all_from_discussion` to construct this thread.
    sig { params(last_read_at: T.untyped).returns(T.untyped) }
    def count_newer_than(last_read_at)
      return 0 if last_read_at.nil?

      if newer_count.zero?
        # If there were >= initial_count replies newer than last_read_at, we may have included up to that many older
        # replies in the results, so we need to adjust accordingly.
        replies.count { |comment| comment.created_at >= last_read_at }
      else
        replies.size + newer_count
      end
    end

    # Public: Compute the total number of visible (non-spam) replies in this thread.
    sig { returns(T.untyped) }
    def total_reply_count
      older_count + newer_count + replies.size
    end
  end
end
