# typed: true
# frozen_string_literal: true

class DiscussionTimeline::Placeholder
  class DiscussionComment
    sig do
      params(
        id: T.untyped,
        parent_comment_id: T.untyped,
        created_at: T.untyped,
        reply_max_count: T.untyped,
        last_read_at: T.untyped
      ).void
    end
    def initialize(id:, parent_comment_id:, created_at:, reply_max_count:, last_read_at: nil)
      @id = id
      @parent_comment_id = parent_comment_id
      @created_at = created_at
      @last_read_at = last_read_at
      @reply_max_count = reply_max_count
      @reply_placeholders = []
      @older_count = 0
      @newer_count = 0
    end

    attr_reader :id, :parent_comment_id, :created_at, :older_count, :newer_count, :reply_placeholders, :last_read_at
    attr_accessor :reply_max_count

    sig { returns(T::Boolean) }
    def top_level_comment?
      parent_comment_id.nil?
    end

    sig { returns(T::Boolean) }
    def reply?
      !parent_comment_id.nil?
    end

    sig { returns(T.untyped) }
    def thread_comments
      [self, reply_placeholders]
    end

    sig { returns(T::Boolean) }
    def has_max_replies?
      reply_placeholders.size == reply_max_count
    end

    sig { returns(T::Boolean) }
    def has_max_unread_replies?
      has_max_replies? && !last_read_at.nil? && reply_placeholders.first.created_at > last_read_at
    end

    sig { params(placeholder: T.untyped).returns(T.untyped) }
    def add_reply(placeholder)
      if has_max_unread_replies?
        @newer_count += 1
      elsif has_max_replies?
        reply_placeholders.shift
        reply_placeholders << placeholder
        @older_count += 1
      else
        reply_placeholders << placeholder
      end
    end
  end
end
