# typed: true
# frozen_string_literal: true

class Actions::WorkflowRunItem::TimingComponent < ApplicationComponent
  include StatusHelper

  def initialize(workflow_run:)
    @workflow_run = workflow_run
  end

  private

  attr_reader :workflow_run

  delegate :duration, to: :workflow_run, private: true
end
