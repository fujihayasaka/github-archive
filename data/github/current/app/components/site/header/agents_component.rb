# typed: true
# frozen_string_literal: true

class Site::Header::AgentsComponent < ApplicationComponent
  attr_reader :agents_panel_payload

  def initialize(
    agents_panel_payload:
  )
    @agents_panel_payload = agents_panel_payload
  end

  def render?
    agents_panel_payload.present?
  end

  def global_agents_button_id
    agents_panel_payload[:agentsButtonId]
  end
end
