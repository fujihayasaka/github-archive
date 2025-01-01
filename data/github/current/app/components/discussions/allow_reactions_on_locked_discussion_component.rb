# typed: true
# frozen_string_literal: true

module Discussions
  class AllowReactionsOnLockedDiscussionComponent < ApplicationComponent
    include FeatureFlagHelper

    # timeline - a DiscussionTimeline
    def initialize(repo_owner:)
      @repo_owner = repo_owner
    end
  end
end
