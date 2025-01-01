# typed: true
# frozen_string_literal: true

module GhostPilot
  class StaticTextComponent < BaseContextComponent
    erb_template <<-ERB
      <span hidden id="<%= element_id %>" data-description="<%= description %>" data-value="<%= context %>"></span>
    ERB

    attr_reader :context, :description, :element_id

    def initialize(context:, description:)
      @context = context
      @description = description
      @element_id = SecureRandom.uuid
    end
  end
end
