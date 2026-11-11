# typed: true
# frozen_string_literal: true

class DeploymentRequest
  attr_reader :environment
  attr_reader :reviewers
  attr_reader :current_user_can_approve
  attr_reader :wait_timer
  attr_reader :wait_timer_started_at

  def initialize(environment, reviewers, current_user_can_approve, wait_timer, wait_timer_started_at)
    @environment = environment
    @reviewers = reviewers
    @current_user_can_approve = current_user_can_approve
    @wait_timer = wait_timer
    @wait_timer_started_at = wait_timer_started_at
  end

end
