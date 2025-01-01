# typed: false
# frozen_string_literal: true

class GateApprovalLog < ApplicationRecord::ActionsEnvironments
  include GitHub::Relay::GlobalIdentification
  enum :state, GateApproval.states

  MAX_COMMENT_LENGTH = 1024
  MAX_COMMENT_COUNT = 10

  include ::Repositories::BelongsToRepository
  flagged_belongs_to_repository_via_domain optional: false
  belongs_to :check_suite, inverse_of: :gate_approval_logs
  belongs_to :user
  has_many :gate_approvals

  after_commit :notify_socket_subscribers

  SIBLING_CANCELLATION_MESSAGE = "Canceled because another deployment protection rule was rejected."

  validates_length_of :comment, maximum: MAX_COMMENT_LENGTH, too_long: "exceeded maximum length of #{MAX_COMMENT_LENGTH} characters."

  def platform_type_name
    "DeploymentReview"
  end

  def self.approve_or_reject_requests(user, gate_requests, state, comment)
    unless %w[approved rejected].include?(state)
      raise ArgumentError, "Invalid state provided"
    end

    gate_request = gate_requests.first
    gate = gate_request.gate
    check_run = gate_request.check_run
    check_suite = check_run.check_suite
    environment = gate.environment
    repository = environment.repository

    gate_request_state = state == "approved" ? :open : :rejected
    gate_approval_log = GateApprovalLog.new({
      repository: repository,
      check_suite: check_suite,
      user: user,
      state: state,
      comment: comment,
    })

    unless gate_approval_log.valid?
      raise ArgumentError, gate_approval_log.errors.full_messages.first
    end

    sibling_gate_requests = []
    if gate_request_state == :rejected
      gate_request_ids = gate_requests.map(&:id)
      check_run_ids = gate_requests.map(&:check_run_id)
      sibling_gate_requests = GateRequest
        .where(check_run_id: check_run_ids, state: "closed")
        .where.not(id: gate_request_ids)
        .to_a
    end

    begin
      gate_requests.each do |gate_request|
        unless gate_request.closed?
          raise ArgumentError, "At least one environment has already been approved or rejected"
        end

        if gate_request.find_matching_gate_approver(user).nil?
          raise ArgumentError, "User is not a valid approver"
        end

        gate = gate_request.gate
        environment = gate.environment
        check_run = gate_request.check_run

        if gate.prevent_self_review? && user == gate_request.requester
          raise ArgumentError, "User may not review their own deployment for this gate"
        end

        # We build the object first, before making the rpc call, so any validation is performed before
        # the call and we are more confident that saving it will succeed
        gate_approval = gate_approval_log.gate_approvals.build({
          gate_request: gate_request,
          repository: repository,
          approver: user,
          state: state,
          user: user,
          environment: environment,
        })

        unless gate_approval.valid?
          raise ArgumentError, "There's a gate that could not be approved"
        end

        run_stamp_url = check_run.check_suite.workflow_run.latest_workflow_run_execution.run_stamp_url
        if run_stamp_url.present?
          request = GitHub::ActionsRunService::Api::Twirp::V1::NotifyGateRequest.new({
            gate_global_id: get_global_id(gate),
            workflow_run_backend_id: check_run.check_suite.external_id,
            workflow_job_run_backend_id: check_run.external_id,
            is_open: state == "approved",
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
            gate_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: get_global_id(gate)),
            external_job_id: check_run.external_id,
            external_id: check_run.check_suite.external_id,
            is_open: state == "approved",
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
          gate_approval.save!

          # Assuming just one approval opens or rejects the gate request
          gate_request.update!(state: gate_request_state)

          siblings = sibling_gate_requests.filter { |gr| gr.check_run_id == gate_request.check_run_id }
          if siblings.any?
            # best effort attempt at canceling sibling gate requests.
            # we don't want to fail the overall rejection if we fail to cancel sibligns
            begin
              cancel_pending_requests(environment: environment, gate_requests: siblings, actor: user, comment: SIBLING_CANCELLATION_MESSAGE)
            rescue ActiveRecord::ActiveRecordError => exception
              Failbot.report(exception)
            end
          end
        else
          raise ArgumentError, "There was a problem approving one of the gates"
        end
      end
    end

    action = state == "approved" ? "approved" : "rejected"
    GitHub::instrument "deployment_review.#{action}", {
        gate_approval_log_id: gate_approval_log.id,
        comment: comment,
        action: action,
    }

    gate_approval_log
  end

  # Reject a list of gate requests
  # This will not send any gate notification requests, it's up to the caller to manage those and cancel any runs
  def self.reject_pending_requests(environment:, gate_requests:, comment:, actor:)
    repository = environment.repository

    # A pending request is one where the gate has not been approved (opened) or rejected yet
    pending_gate_requests = gate_requests.filter(&:closed?)
    rejected_gate_requests = []

    gate_approval_log_hash = Hash.new

    pending_gate_requests.each do |gate_request|
      check_suite = gate_request.check_run.check_suite
      gate_approval_log = gate_approval_log_hash[check_suite.id]
      transaction do
        unless gate_approval_log.present?
          gate_approval_log = GateApprovalLog.create!({
            repository: repository,
            check_suite: check_suite,
            user: actor,
            state: :rejected,
            comment: comment,
          })

          gate_approval_log_hash[check_suite.id] = gate_approval_log
        end

        # The gate request should not exist in the approval log yet since the request is still pending
        gate_approval_log.gate_approvals.create!({
          gate_request: gate_request,
          repository: repository,
          approver: actor,
          state: :rejected,
          user: actor,
          environment: environment,
        })
        gate_request.update!(state: :rejected)
      end
      rejected_gate_requests << gate_request
    end

    rejected_gate_requests
  end

  # This creates gate approval logs with "canceled" state for the given gate requests.
  # This will not send any gate notification requests, it's up to the caller to manager those and reject any runs.
  def self.cancel_pending_requests(environment:, gate_requests:, actor:, comment:)
    gate_requests.filter { |gate_request| gate_request.closed? }.each do |gate_request|
      # use environment from the caller rather than `gate_request.gate.environment` since gate could be deleted
      repository = environment.repository
      check_run = gate_request.check_run

      if check_run.nil?
        GitHub.logger.info(
          "Unable to find check run #{gate_request.check_run_id} when cancelling pending gate request #{gate_request.id}",
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.repository.id" => repository.id,
          "gh.repository.check_run_id" => gate_request.check_run_id,
          "gh.repository.environment.id" => environment.id,
          "gh.repository.environment.gate.gate_request.id" => gate_request.id,
        )
        next
      end

      transaction do
        gate_approval_log = GateApprovalLog.create!({
          repository: repository,
          check_suite_id: check_run.check_suite_id,
          user: actor,
          state: :canceled,
          comment: comment,
        })
        gate_approval_log.gate_approvals.create!({
          gate_request: gate_request,
          repository: repository,
          approver: actor,
          state: :canceled,
          user: actor,
          environment: environment,
        })
        gate_request.update!(state: :rejected)
      end
    end
  end

  # Create a gate approval log for an "open" timeout gate request with state "approved"
  # Since timeout gate requests are managed by the actions backend, we rely on postbacks to tell us when the gate
  # request is open. Once open we can backfill the approval log, other gate request approval logs are created
  # immediately when the user performs an action (i.e. reject/cancel).
  def self.backfill_for_timeout_gate_postback(environment:, gate_request:, comment:, actor:)
    if !gate_request.gate.timeout? || gate_request.state != "open"
      raise ArgumentError, "Invalid gate request provided"
    end

    repository = environment.repository
    check_suite = gate_request.check_run.check_suite
    state = "approved"

    transaction do
      gate_approval_log = GateApprovalLog.new({
        repository: repository,
        check_suite: check_suite,
        user: actor,
        state: state,
        comment: comment,
      })

      gate_approval_log.gate_approvals.build({
        gate_request: gate_request,
        repository: repository,
        approver: actor,
        state: state,
        user: actor,
        environment: environment,
      }).save!
    end
  end

  def self.skip_requests(actor:, gate_requests:, comment:)
    if gate_requests.nil?
      raise ArgumentError, "No pending gates found for this environment"
    end

    unless gate_requests.first.gate.environment.repository.adminable_by?(actor) &&
      gate_requests.map(&:gate).map(&:environment).map(&:repository_id).uniq.length == 1
      raise ArgumentError, "User is not an admin of the repository"
    end

    pending_gate_requests = gate_requests.select { |request| request.closed? }
    gate_approval_logs = []

    begin
      pending_gate_requests.each do |gate_request|
        gate = gate_request.gate
        environment = gate.environment
        repository = environment.repository
        check_run = gate_request.check_run
        check_suite = check_run.check_suite

        gate_approval_log = GateApprovalLog.new({
          repository: repository,
          check_suite: check_suite,
          user: actor,
          state: "skipped",
          comment: comment,
        })

        unless gate_approval_log.valid?
          raise ArgumentError, gate_approval_log.errors.full_messages.first
        end

        # We build the object first, before making the rpc call, so any validation is performed before
        # the call and we are more confident that saving it will succeed
        gate_approval = gate_approval_log.gate_approvals.build({
          gate_request: gate_request,
          repository: repository,
          approver: actor,
          state: "skipped",
          user: actor,
          environment: environment,
        })


        run_stamp_url = check_run.check_suite.workflow_run.latest_workflow_run_execution.run_stamp_url
        if run_stamp_url.present?
          request = GitHub::ActionsRunService::Api::Twirp::V1::NotifyGateRequest.new({
            gate_global_id: get_global_id(gate),
            workflow_run_backend_id: check_run.check_suite.external_id,
            workflow_job_run_backend_id: check_run.external_id,
            is_open: true,
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
              gate_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: get_global_id(gate)),
              external_job_id: check_run.external_id,
              external_id: check_run.check_suite.external_id,
              is_open: true,
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
          gate_approval.save!

          # Assuming just one skip opens the gate request
          gate_request.update!(state: "open")

          gate_approval_log.save!
          gate_approval_logs << gate_approval_log
        else
          raise ArgumentError, "There was a problem skipping one of the gates"
        end
      end
    end

    gate_approval_logs
  end

  def self.post_comment_for_pending_custom_gate_requests(actor, gate_requests, comment)
    return unless gate_requests.first.gate.custom?

    GitHub::PrefillAssociations.prefill_associations(gate_requests, :gate_approvals)

    environment = gate_requests.first.gate.environment
    repository =  environment.repository
    check_suite = gate_requests.first.check_run.check_suite
    state = "pending"

    # one GateApprovalLog entry
    gate_approval_log = GateApprovalLog.new({
      repository: repository,
      check_suite: check_suite,
      user: actor,
      state: state,
      comment: comment,
    })

    unless gate_approval_log.valid?
      raise ArgumentError, gate_approval_log.errors.full_messages.first
    end

    gate_requests.each do |gate_request|
      unless gate_request.closed?
        raise ArgumentError, "At least one environment has already been approved or rejected. You can only comment on pending requests."
      end

      if gate_request.find_matching_gate_approver(actor).nil?
        raise ArgumentError, "GitHub App is not a valid approver and cannot make a comment."
      end

      if gate_request.gate_approvals.to_a.count { |gate_approval| gate_approval.state == "pending" } >= MAX_COMMENT_COUNT
        raise ArgumentError, "You have exceeded the maximum allowed comments of #{MAX_COMMENT_COUNT} for the pending approval in environment #{environment.name}."
      end

      gate_approval_log.gate_approvals.build({
        gate_request: gate_request,
        repository: repository,
        approver: actor,
        state: state,
        user: actor,
        environment: environment,
      }).save!
    end
  end

  def notify_socket_subscribers
    return if check_suite.workflow_run.nil?
    data = {
      timestamp: updated_at,
      wait: default_live_updates_wait,
      reason: "Gate approval log created or updated",
    }
    GitHub::WebSocket.notify_repository_channel(check_suite.repository, check_suite.workflow_run.approval_logs_channel, data)
  end

  def user
    super || User.ghost
  end

  def self.get_global_id(entity)
    !GitHub.enterprise? ? entity.next_global_id : entity.global_relay_id
  end
  private_class_method :get_global_id
end
