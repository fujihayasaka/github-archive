# typed: true
# frozen_string_literal: true

module Releases
  class MarketplaceLabelComponent < ApplicationComponent
    def initialize(release, **system_arguments)
      @release = release
      @system_arguments = system_arguments
    end

    attr_reader :release, :system_arguments

    def action_release
      @release.repository_action_release
    end

    def hydro_data
      hydro_payload = {
        repository_action_id: action_release.repository_action.id,
        source_url: request&.url,
        location: controller.controller_name + "#" + (controller.action_name || "")
      }

      hydro_click_tracking_attributes("marketplace.action.click", hydro_payload)
    end
  end
end
