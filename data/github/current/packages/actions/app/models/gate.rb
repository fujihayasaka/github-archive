# typed: false
# frozen_string_literal: true

class Gate < ApplicationRecord::Domain::Repositories
  self.inheritance_column = nil
  self.ignored_columns = %w(name)


  enum :type, { timeout: 0, manual_approval: 1, branch_policy: 2, custom: 3 }

  after_initialize :set_initial_state
  after_commit :reject_pending_gate_requests, on: :destroy
  after_commit :instrument_creation, on: :create
  after_commit :instrument_destruction, on: :destroy

  belongs_to :environment
  has_many :gate_requests
  has_many :gate_approvers, autosave: true
  has_many :branch_policies, class_name: "GateBranchPolicy", autosave: true
  belongs_to :integration, optional: true

  # Don't destroy gate_requests here.
  # We need to reject pending gate requests when the gate is deleted.
  # This will cause the runs associated with those gate requests to be cancelled by a background job,
  # but that will break if the gate requests are deleted.
  destroy_dependents_in_background :gate_approvers
  destroy_dependents_in_background :branch_policies

  MAX_TIMEOUT_MINUTES = 43_200 # 30 days (60*24*30)
  validates(:timeout, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than: MAX_TIMEOUT_MINUTES })

  MAX_APPROVERS = 6

  PROTECTED_BRANCHES = "protected_branches"

  def set_approvers(approvers)
    # We always want to replace the approvers
    gate_approvers.destroy_all unless self.new_record?

    approvers.each do |approver|
      gate_approvers.create!(repository: environment.repository, approver: approver)
    rescue ActiveRecord::RecordInvalid
      # Ignore invalid approvers
    end
  end

  def reject_pending_gate_requests
    # do nothing if the environment was destroyed. This can happen when a repository is deleted
    return if environment.nil? || environment.repository.nil?
    actor = User.find_by(id: GitHub.context[:actor_id])
    requests = gate_requests.includes(check_run: [:check_suite]).where(state: :closed)
    GateApprovalLog.cancel_pending_requests(environment: environment, gate_requests: requests, actor: actor, comment: log_deletion_comment)
    NotifyRejectedGatesJob.perform_later(gate_request_ids: requests.map(&:id), repository_global_relay_id: get_global_id(environment.repository), gate_global_relay_id: get_global_id(self))

  end

  def protected_branch_gate?
    return false unless branch_policy?
    return false if body.nil? || body.empty?
    json_body = JSON.parse(body)
    json_body[PROTECTED_BRANCHES]
  end

  private

  def instrument_creation
    if timeout?
      environment.instrument_event(event: "add_protection_rule", gate_type: type, timeout: timeout)
    elsif manual_approval?
      approvers = gate_approvers.includes(:approver).collect(&:approver)
      environment.instrument_event(event: "add_protection_rule", gate_type: type, approvers: approvers)
    elsif custom?
      # include the enitre integration record, otherwise the audit log will not be able to render the integration name
      # in the event that the integration is deleted
      environment.instrument_event(event: "add_protection_rule", gate_type: type, integration: integration)
    end
  end

  def instrument_destruction
    return if environment.nil? || environment.destroyed? || branch_policy?
    if custom?
      # include the enitre integration record, otherwise the audit log will not be able to render the integration name
      # in the event that the integration is deleted
      environment.instrument_event(event: "remove_protection_rule", gate_type: type, integration: integration)
    else
      environment.instrument_event(event: "remove_protection_rule", gate_type: type)
    end
  end

  def set_initial_state
    self.timeout ||= 0
    self.body ||= ""
  end

  def log_deletion_comment
    case type
    when "timeout"
      "Wait timer protection rule deleted."
    when "manual_approval"
      "Required reviewers protection rule deleted."
    when "custom"
      "Custom protection rule deleted."
    else
      "Protection rule deleted."
    end
  end

  def get_global_id(entity)
    !GitHub.enterprise? ? entity.next_global_id : entity.global_relay_id
  end
end
