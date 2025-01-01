# typed: true
# frozen_string_literal: true

module SecurityCenter
  class StatesComponent < ApplicationComponent
    attr_reader \
      :closed_state_count,
      :closed_state_href,
      :closed_state_selected,
      :open_state_count,
      :open_state_href,
      :open_state_selected,
      :system_arguments

    def initialize(
      closed_state_count:,
      closed_state_href:,
      closed_state_selected:,
      open_state_count:,
      open_state_href:,
      open_state_selected:,
      **system_arguments
    )
      @closed_state_count = closed_state_count
      @closed_state_href = closed_state_href
      @closed_state_selected = closed_state_selected

      @open_state_count = open_state_count
      @open_state_href = open_state_href
      @open_state_selected = open_state_selected

      @system_arguments = system_arguments
    end
  end
end
