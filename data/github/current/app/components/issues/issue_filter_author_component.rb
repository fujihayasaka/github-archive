# typed: true
# frozen_string_literal: true

module Issues
  class IssueFilterAuthorComponent < ApplicationComponent
    include AvatarHelper
    include BotHelper

    def initialize(user:, url:, selected:)
      @user, @url, @selected = user, url, selected
    end
  end
end
