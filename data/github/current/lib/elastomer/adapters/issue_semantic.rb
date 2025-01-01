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
      @hash
    end

    def comment_hash(comment)
      hash = super
      hash.delete(:body) if comment.body.blank?
      hash
    end
  end
end
