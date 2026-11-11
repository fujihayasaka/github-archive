# typed: true
# frozen_string_literal: true

class Issues::References::PullRequestComponent < ApplicationComponent
  attr_reader :pull_request, :checked, :disabled

  def render?
    !@pull_request.nil?
  end

  # pull_request: PullRequest
  #  The pull request to link or not link to issue
  # checked: Boolean
  #   True if the pull request is linked to the issue
  # disabled: Boolean
  #   True if the pull request is a manually linked reference,
  #   e.g. "closes" in a pull request
  def initialize(pull_request:, checked: false, disabled: false)
    @pull_request = pull_request
    @checked = checked
    @disabled = disabled
  end

  def octicon_name
    if @pull_request.open?
      "git-pull-request"
    elsif @pull_request.merged?
      "git-merge"
    elsif @pull_request.closed?
      "git-pull-request-closed"
    end
  end

  def octicon_color
    if @pull_request.open?
      :success
    elsif @pull_request.merged?
      :done
    elsif @pull_request.closed?
      :danger
    end
  end

end
