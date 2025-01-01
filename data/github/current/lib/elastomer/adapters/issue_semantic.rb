# typed: true
# frozen_string_literal: true

require "scientist"

module Elastomer::Adapters
  # The Issue adapter is used to transform an issue ActiveRecord object into a
  # Hash document that can be indexed in ElasticSearch.
  #
  class IssueSemantic < ::Elastomer::Adapters::Issue

    def self.index_name
      "IssuesSemantic"
    end

    def to_hash
      @hash = super
      @hash.delete(:title) if issue.title.blank?
      @hash.delete(:body) if issue.body.blank?

      unless GitHub.flipper[:issues_semantic_serialize_milestone_priorities].enabled?
        # This is a workaround for the issue where the inference endpoint
        @hash.delete(:milestone_prio)
      end
      @hash
    end

    def comment_hash(comment)
      hash = super
      hash.delete(:body) if comment.body.blank?
      hash
    end

    def comments_for(issue)
      comments = []

      scope = issue.comments.includes(:reactions).not_spammy.limit(::Issue::COMMENT_LIMIT)

      scope.find_in_batches(batch_size: COMMENT_BATCH_SIZE) do |batch|
        batch.each do |comment|
          hash = comment_hash(comment)
          # Only thing we really change here is this line:
          # - We default to empty string if body is nil, as we delete it to workaround inference endpoint bug
          increment_bytesize(hash.fetch(:body, ""))

          # Once max_bytesize is exceeded, stop converting comments
          if bytesize_estimate > max_bytesize
            break
          else
            comments << hash
          end
        end
      end

      comments.compact
    end
  end
end
