# typed: true
# frozen_string_literal: true

class Actions::Graph::StageComponent < ApplicationComponent
  def initialize(stage:, workflow_run:, execution: nil, retry_blankstate: false, pull_request_number: nil)
    @stage = stage
    @workflow_run = workflow_run
    @execution = execution
    @retry_blankstate = retry_blankstate
    @pull_request_number = pull_request_number
  end

  private

  attr_reader :stage, :workflow_run
end
