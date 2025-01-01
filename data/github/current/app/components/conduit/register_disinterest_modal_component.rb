# typed: true
# frozen_string_literal: true

module Conduit
  class RegisterDisinterestModalComponent < ApplicationComponent
    attr_reader :item
    delegate :actor, :subject, :source, :event_id, :resource_id, :resource_type, :event_type, :content_type, :identifier, to: :item

    def initialize(item:)
      @item = item
    end

    def show_less_activity_hydro_click_attributes(item)
      return unless item

      payload = {
        actor_id: current_user&.id,
        resource_id: item.subject&.id,
        resource_type: item.resource_type,
        event_id: item.event_id,
        event_type_string: item.event_type.to_s,
        clicked_at: Time.current.to_i,
        identifier: item.identifier,
        source: item.source,
        originating_url: request&.original_url,
      }

      hydro_click_tracking_attributes("browser.feed.show_less_activity_button.click", payload)
    end
  end
end
