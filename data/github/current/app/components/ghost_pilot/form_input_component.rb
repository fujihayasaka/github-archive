# typed: true
# frozen_string_literal: true

module GhostPilot
  class FormInputComponent < BaseContextComponent
    erb_template <<-ERB
      <span hidden id="<%= element_id %>" data-description="<%= element_description %>" data-reference="<%= target_element_id %>"></span>
    ERB

    attr_reader :target_element_id, :element_description

    def initialize(target_element_id:, element_description: nil)
      @target_element_id = target_element_id
      @element_description = element_description || target_element_id.split("_").map(&:capitalize).join(" ")
    end

    def element_id
      "input-reference-#{target_element_id}"
    end
  end
end
