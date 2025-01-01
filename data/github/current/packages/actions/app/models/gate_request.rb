# typed: false
# frozen_string_literal: true

class GateRequest < ApplicationRecord::Domain::Repositories
  enum :state, { closed: 0, open: 1, rejected: 2 }

  belongs_to :gate
  belongs_to :check_run
  has_many :gate_approvals

  after_commit :instrument_creation, on: [:create]
  after_commit :deliver_notifications, on: [:create]
  after_commit :notify_socket_subscribers, on: [:create, :update]
  after_commit :instrument_deployment_protection_rule_requested_event, on: [:create]
  after_commit :backfill_gate_approval_log_for_timeout_gate_request, on: [:update]

  def expired?
    # rejection happens when the gate is "really closed", so we should check for that state
    expires_at && state.to_s == "rejected" && updated_at > expires_at
  end

  def self.create_or_update_gate_request(gate_id, check_run, token, state, concluded = false, expires_at = nil)
    gate_id = gate_id.id if gate_id.is_a? Gate # We accept a gate instance or an id. Get the id when it's an instance
    find_by_attrs = { check_run: check_run, gate_id: gate_id }
    gate_request = GateRequest.retry_on_find_or_create_error do
      gate_request = GateRequest.find_by(find_by_attrs) || GateRequest.new(find_by_attrs)
      gate_request.token = token.present? ? token : ""
      gate_request.expires_at = expires_at if expires_at.present?

      if state.present?
        transition_to_state = state
        if state.to_s == "closed"
          # Actions Service only tells us if a gate is open or closed,
          # but we also track if a gate request has been rejected
          # rejection is to say that the gate is "really closed" ("closed" + "concluded")
          # Rejection happens when: user rejects approval, user deletes deletes gate, user deletes environment, gate timed out
          # So if a gate request is rejected, don't update back to "closed."
          # Checkout https://github.com/github/c2c-actions-service/issues/1769 for more details
          transition_to_state = :rejected if gate_request.rejected? || concluded
        end

        gate_request.state = transition_to_state
      end

      gate_request.save!
      gate_request
    end
    check_run.update_status_and_deployment_from_gates
    if !concluded && gate_request.gate&.branch_policy?
      self.evaluate_branch_policy(gate_request, check_run)
    end

    gate_request
  end

  def requester
    # For Actions, check_run.creator is nil, but check_suite.creator has the correct value
    check_run.check_suite.creator
  end

  def approval_status(user)
    return unless user.present?
    return if gate.present? && gate.prevent_self_review && user == requester

    gate_approvals.each do |gate_approval|
      return gate_approval.state if gate_approval.user.id == user.id && gate_approval.state != "pending"
    end

    return "pending" if find_matching_gate_approver(user)
    nil
  end

  def find_matching_gate_approver(user)
    return unless gate.present?

    if gate.custom? && user.is_a?(Bot)
      return unless gate.integration_id == user&.integration.id
      return user
    elsif gate.manual_approval? && (user.is_a?(User) || user.is_a?(Team))
      gate_approver = find_manual_approval_gate_approver(user)
      # when we have found a gate_approver that matches the given user, we need to ensure that the gate_approver
      # still has valid associations with the repository. To do this we call .valid? on the gate_approver, but first
      # we need to prefill it's associations since find_manual_approval_gate_approver(...) does not preload
      # dependencies. Prefilling associations is necessary because this method is used by GraphQL resolvers which
      # will refuse adhoc queries to load associations (to help minimize n+1 queries), and if we had done it
      # earlier in the process it would have been wasted since the user might not have matched a gate approver.
      #
      # https://thehub.github.com/epd/engineering/products-and-services/public-apis/graphql/debugging/common-errors/#associationloaded--associationrefused
      if gate_approver.present?
        GitHub::PrefillAssociations.prefill_associations(gate_approver, [:approver, { repository: [:organization, :owner] }])
        return gate_approver if gate_approver.valid?
      end
    end

    nil
  end

  private def find_manual_approval_gate_approver(user)
    gate.gate_approvers.find do |gate_approver|
      approver = gate_approver.approver
      # when an approver is deleted(likely a team), continue on to find any other valid approvers
      next if approver.nil?

      if approver.is_a?(User)
        return gate_approver if approver.id == user.id
      else
        team = approver
        return gate_approver if Team.member_of?(team.id, user.id, immediate_only: false)
      end
    end
  end


  def self.evaluate_branch_policy(gate_request, check_run)
    datadog_tags = []
    check_suite = check_run.check_suite
    environment = gate_request.gate.environment
    repository = environment.repository

    is_open = false
    if environment.branch_policy_gate_branch_protected?
      branch_patterns = repository.protected_branches
    else
      branch_patterns = gate_request.gate.branch_policies
    end

    if branch_patterns.empty?
      is_open = true # Always open the gate if there are no branches specified for the policy
    elsif !environment.branch_policy_gate_branch_protected?
      # Match tag rules if run is triggered from a tag
      if check_suite.head_branch(fully_qualified: true).starts_with?("refs/tags/")
        branch_patterns.each do |branch_pattern|
          if branch_pattern.is_tag_policy? && branch_pattern.matches?(check_suite.head_branch)
            is_open = true
            break
          end
        end
      else
        branch_patterns.each do |branch_pattern|
          if !branch_pattern.is_tag_policy? && branch_pattern.matches?(check_suite.head_branch)
            is_open = true
            break
          end
        end
      end
    else
      branch_patterns.each do |branch_pattern|
        if branch_pattern.matches?(check_suite.head_branch)
          is_open = true
          break
        end
      end

      if is_open && branch_policy_should_block_forks_and_tags?(repository, check_suite)
        # If we can't find head_branch in the list of branches containing head_sha then we assume the head_ref is from a tag or fork
        is_open = false
        GitHub.logger.info({
          "method": "evaluate_branch_policy",
          "message": "branch policy evaluation failed because check_suite head_branch is not in the list of branches containing head_sha",
          "nwo": repository.name_with_display_owner,
          "check_suite_id": check_suite.id,
          "head_sha": check_suite.head_sha,
          "head_branch": check_suite.head_branch,
        })
      end
    end

    run_stamp_url = check_suite.workflow_run.latest_workflow_run_execution.run_stamp_url

    if run_stamp_url.present?
      request = GitHub::ActionsRunService::Api::Twirp::V1::NotifyGateRequest.new({
        gate_global_id: get_global_id(gate_request.gate),
        workflow_run_backend_id: check_suite.external_id,
        workflow_job_run_backend_id: gate_request.check_run.external_id,
        is_open: is_open,
      })

      client = if ActionsRunService.is_lab_url?(run_stamp_url)
        ActionsRunService::Twirp::RunServiceLabClient.new(base_url: run_stamp_url)
      else
        ActionsRunService::Twirp::RunServiceClient.new(base_url: run_stamp_url)
      end
      result = client.notify_gate(request)
    else
      request = GitHub::Launch::Services::Environment::NotifyGateRequest.new({
        repository_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: get_global_id(repository)),
        gate_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: get_global_id(gate_request.gate)),
        external_job_id: gate_request.check_run.external_id,
        external_id: check_suite.external_id,
        is_open: is_open,
        token: gate_request.token,
        check_suite_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: get_global_id(check_suite)),
      })

      result = if check_suite.github_app.launch_lab_github_app?
        Launch::Twirp::environment_lab_client.notify_gate(request)
      else
        Launch::Twirp::environment_client.notify_gate(request)
      end
    end

    if result.call_succeeded?
      gate_request.update(state: is_open ? :open : :rejected)
      unless is_open
        datadog_tags << "state:rejected"
        check_run.annotations.create!(
          message: "#{check_suite.head_branch(fully_qualified: true).starts_with?("refs/tags/") ? "Tag" : "Branch"} \"#{check_suite.head_branch}\" is not allowed to deploy to #{environment.name} due to environment protection rules.",
          path: ".github",
          warning_level: "failure",
          start_line: 1,
          repository: check_run.repository,
          end_line: 1)
      end
    else
      GitHub.dogstats.increment("gate_request.evaluate_branch_policy", tags: ["error:true"])
      raise ArgumentError, "Unable to evaluate gate request branch policy"
    end

    GitHub.dogstats.increment("gate_request.evaluate_branch_policy", tags: datadog_tags)
  end

  def approval_notification
    @approval_notification ||= WorkflowRunApprovalNotification.new(check_run.check_suite.workflow_run)
  end

  def requires_manual_action?
    gate&.type == "manual_approval" && closed?
  end

  def workflow_run
    return @workflow_run if defined?(@workflow_run)
    @workflow_run ||= check_run&.check_suite&.workflow_run
  end

  def approver_ids
    return @approvers if defined?(@approvers)
    @approvers ||= get_approvers
  end

  private_class_method :evaluate_branch_policy

  private

  BATCH_SIZE = 100

  def deliver_notifications
    return unless workflow_run.present? && requires_manual_action?
    return unless approver_ids.present?

    approver_ids.each_slice(BATCH_SIZE) do |approver_ids_slice|
      GitHub.newsies.trigger(
        approval_notification,
        recipient_ids: approver_ids_slice,
        reason: :approval_requested,
        event_time: Time.now
      )
    end
  end

  def get_approvers
    gate_approvers = GateApprover.where(gate_id: gate_id)
    gate_approver_users, gate_approver_teams = gate_approvers.partition { |gate_approver| gate_approver.approver.is_a?(User) }
    ids = gate_approver_users.map(&:approver_id) + Team.members_of(gate_approver_teams.map(&:approver_id), immediate_only: false).pluck(:id)
    ids.uniq
  end

  def instrument_creation
    return unless gate.present? && check_run.present?

    GlobalInstrumenter.instrument("gate_request.created", {
      gate_request_id: id,
      gate_id: gate_id,
      gate_type: gate.type,
      check_suite_id: check_run.check_suite_id,
      check_run_id: check_run.id,
      repository: check_run.repository,
      integration: gate.integration
    })
  end

  def notify_socket_subscribers
    return unless check_run.check_suite.present? && check_run.check_suite.workflow_run.present?

    data = {
      timestamp: updated_at,
      wait: default_live_updates_wait,
      reason: "Gate request created or updated",
    }
    GitHub::WebSocket.notify_repository_channel(check_run.check_suite.repository, check_run.check_suite.workflow_run.gate_requests_channel, data)
  end

  def instrument_deployment_protection_rule_requested_event
    return unless gate&.custom?

    GitHub::instrument "deployment_protection_rule.requested", {
        gate_id: gate.id,
        check_run_id: check_run.id,
        action: "requested",
        specific_app_only: true,
    }
  end

  def backfill_gate_approval_log_for_timeout_gate_request
    return unless gate&.timeout?
    return unless open?
    return unless state_previously_was != "open"
    return unless gate_approvals.size == 0

    GateApprovalLog.backfill_for_timeout_gate_postback(
      environment: gate.environment,
      gate_request: self,
      comment: "#{gate.timeout} minute wait timer",
      actor: User.find(GitHub.launch_github_app.bot.id),
    )
  end

  def self.get_global_id(entity)
    !GitHub.enterprise? ? entity.next_global_id : entity.global_relay_id
  end
  private_class_method :get_global_id

  def self.branch_policy_should_block_forks_and_tags?(repository, check_suite)
    # Add an exemption for some repo and repo owners
    return false if GitHub.flipper[:branch_policy_tags_exempt].enabled?(repository) || GitHub.flipper[:branch_policy_tags_exempt].enabled?(repository.owner)
    !repository.rpc.branch_contains(check_suite.head_sha).include?(check_suite.head_branch)
  end
  private_class_method :branch_policy_should_block_forks_and_tags?
end
