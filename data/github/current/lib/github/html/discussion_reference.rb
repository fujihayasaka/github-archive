# typed: true
# frozen_string_literal: true

module GitHub::HTML
  # Object added to the result hash to record discussion references.
  class DiscussionReference
    attr_accessor :discussion, :readable
    alias_method :readable?, :readable

    def initialize(discussion, readable = false)
      @discussion = discussion
      @readable = readable
    end

    def async_repo_and_owner
      discussion.async_repository.then do |repo|
        next unless repo
        repo.async_owner
      end
    end

    def hash
      discussion.hash
    end

    def belonging
      discussion
    end

    def ==(other)
      discussion == other.discussion
    end
    alias_method :eql?, :==
  end
end
