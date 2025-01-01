# typed: true
# frozen_string_literal: true

module Issues
  class IssueAssigneePickerComponent < ApplicationComponent
    include AvatarHelper
    include BotHelper

    def initialize(user:, assigned:, single_select:, profile_name:)
      @user, @assigned, @single_select, @profile_name = user, assigned, single_select, profile_name
      @login = user.display_login_legacy

      # Fall back to their alias if there is no supplied profile_name
      # This is consistent with `safe_profile_name` in user.rb
      @profile_name = @login if @profile_name.blank?
    end
  end
end
