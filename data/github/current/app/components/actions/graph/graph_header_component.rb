# typed: true
# frozen_string_literal: true

class Actions::Graph::GraphHeaderComponent < ApplicationComponent
  def initialize(name:, trigger:, href:, is_required_workflow_execution:)
    @name = name
    @trigger = trigger
    @href = href
    @is_required_workflow_execution = is_required_workflow_execution
  end

  def render_workflow_link?
    href.present?
  end

  private

  attr_reader :name, :trigger, :href, :is_required_workflow_execution
end
