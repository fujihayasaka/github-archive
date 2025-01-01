# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class UserLinkComponent < ApplicationComponent
    attr_reader :user

    def initialize(user:)
      @user = user
    end
  end
end
