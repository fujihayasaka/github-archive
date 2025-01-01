# typed: true
# frozen_string_literal: true

module Api::Serializer
  class IssueCommentishTextMatch
    include TextMatch

    def self.supported_field_names
      %w(comments.body).freeze
    end

    def object_type
      case comment_type
      when "issue"  then "IssueComment"
      when "review" then "ReviewComment"
      end
    end

    def object_url_suffix
      case comment_type
      when "issue"
        "/repositories/#{issue.repository_id}/issues/comments/#{comment_id}"
      when "review"
        "/repositories/#{issue.repository_id}/pulls/comments/#{comment_id}"
      end
    end

    def property
      "body"
    end

    private

    def issue
      search_result["_model"]
    end

    def comment_hashes
      search_result["_source"].fetch("comments", [])
    end

    def comment_hash
      @comment_hash ||= comment_hashes.find { |c| c["body"].include?(text) }
    end

    def comment_id
      comment_hash && comment_hash["comment_id"]
    end

    def comment_type
      comment_hash && comment_hash["comment_type"]
    end
  end
end
