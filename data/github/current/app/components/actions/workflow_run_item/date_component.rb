# typed: true
# frozen_string_literal: true

class Actions::WorkflowRunItem::DateComponent < ApplicationComponent
  def initialize(workflow_run:)
    @workflow_run = workflow_run
  end

  private

  attr_reader :workflow_run
end
