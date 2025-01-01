# typed: true
# frozen_string_literal: true

module Notifications
  class EmailMuteView
    # Controls the email mute view for a user.
    def initialize(summary_response, mute_response)
      @summary_response = summary_response
      @mute_response = mute_response
    end

    # Public: Should we attempt to show the email m ute view or not. If true,
    # yes. If false, we should let the user know that notifications
    # are unavailable.
    #
    # IMPORTANT: Any new notifications calls should be checked here as well.
    #
    # Returns true or false.
    def success?
      @summary_response.success? &&
        (@mute_response.nil? || @mute_response.success?)
    end

    def failed?
      !success?
    end
  end
end
