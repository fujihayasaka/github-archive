# typed: true
# frozen_string_literal: true

module Conduit
  class EventVisibilityFormComponent < ApplicationComponent
    attr_reader :event_id

    def initialize(is_hidden:, event_id:)
      @is_hidden = is_hidden
      @event_id = event_id
    end

    def form_method
      hidden? ? :delete : :post
    end

    def form_path
      activities_visibility_path(current_user)
    end

    def button_text
      if hidden?
        "Unhide event"
      else
        "Hide event"
      end
    end

    def event_hmac
      Conduit.hmac_for_event_id(event_id)
    end

    private

    def hidden?
      @is_hidden
    end
  end
end
