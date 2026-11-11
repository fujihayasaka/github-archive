# typed: true
# frozen_string_literal: true

class CodeScanning::ToolStatus::ScanEventComponent < ApplicationComponent
  attr_reader :event

  BRANCHES_LIMIT = 10

  def initialize(event:, branches:)
    @event = event
    @branches = Array(branches)
  end

  def branches
    @branches.first(BRANCHES_LIMIT)
  end

  def more_branches_text
    return nil if @branches.length <= BRANCHES_LIMIT
    more = @branches.length - BRANCHES_LIMIT
    "#{more} other branch #{'pattern'.pluralize(more)}"
  end

  def event_text
    case event
    when "push" then "Push to "
    when "pull_request" then "Pull request to "
    when "workflow_dispatch" then "Workflow dispatch"
    else event
    end
  end
end
