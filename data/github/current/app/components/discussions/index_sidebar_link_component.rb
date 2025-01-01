# typed: true
# frozen_string_literal: true

module Discussions
  class IndexSidebarLinkComponent < ApplicationComponent
    def initialize(hydro_event_category:, hydro_event_action: , test_id:, icon:, text:, href:, wrap_text: true)
      @hydro_event_category = hydro_event_category
      @hydro_event_action = hydro_event_action
      @test_id = test_id
      @icon = icon
      @text = text
      @href = safe_uri(href).blank? ? "#" : href
      @wrap_text = wrap_text
    end

    attr_reader  :test_id, :icon , :text, :href , :wrap_text, :hydro_event_category, :hydro_event_action
  end
end
