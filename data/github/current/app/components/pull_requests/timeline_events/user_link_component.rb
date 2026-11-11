# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class UserLinkComponent < ApplicationComponent
    attr_reader :user

    delegate :profile_link_user_name_display_configuration, to: :helpers

    def initialize(user:)
      @user = user
    end
  end
end
