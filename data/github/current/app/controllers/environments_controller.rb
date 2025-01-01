# typed: true
# frozen_string_literal: true

class EnvironmentsController < AbstractRepositoryController
  before_action :login_required
  before_action :ensure_can_use_environments

  def approve_or_reject_gate_requests # rubocop:todo GitHub/UseRestfulActions
    state = params[:decision]
    comment = params[:comment] || ""

    unless %w[approved rejected].include? state
      flash[:error] = "Unsupported decision value."
      redirect_to :back and return
    end

    unless params[:gate_request].present?
      flash[:error] = "No approval request was selected."
      redirect_to :back and return
    end

    begin
      # `params[:gate_request]` will be an array like ["1,2", "3"]
      # The comma-delimited sequences of IDs are for the same environment and are grouped together in the form.
      all_gate_requests = params[:gate_request].flat_map { |id| id.split(",").map(&:to_i) }
      # Ensure we are scoping to current repository for CAP enforcement, see https://github.com/github/c2c-actions-service/issues/1883
      # ...for that we have to include `environment`, since only an environment is scoped to repository
      gate_requests = GateRequest.includes(gate: [environment: :repository]).where(repository: { id: current_repository.id }).find(all_gate_requests)
      GateApprovalLog.approve_or_reject_requests(current_user, gate_requests, state, comment)
      flash[:notice] = "The deployments have been #{state}."
    rescue ArgumentError
      flash[:error] = "There was a problem approving one of the gates."
    rescue ActiveRecord::RecordNotFound
      flash[:error] = "Gate requests are not found."
    end

    redirect_to :back
  end

  def skip_pending_gate_requests # rubocop:todo GitHub/UseRestfulActions
    if !current_repository.adminable_by?(current_user)
      flash[:error] = "You do not have permission to skip pending deployment protection rules."
      redirect_to :back and return
    end
    unless params[:gate_request].present?
      flash[:error] = "No environment was selected."
      redirect_to :back and return
    end

    comment = params[:comment] || ""

    # `params[:gate_request]` will be an array like ["1,2", "3"]
    # The comma-delimited sequences of IDs are for the same environment and are grouped together in the form.
    gate_request_ids = params[:gate_request].flat_map { |id| id.split(",").map(&:to_i) }

    begin
      gate_requests = GateRequest.includes(gate: [:environment])
        .where(environment: { gates_admin_enforced: false, repository_id: current_repository.id }, state: "closed")
        .find(gate_request_ids)
        .to_a

      if !gate_requests.any?
        flash[:error] = "There are no pending deployment protection rules to skip."
        redirect_to :back and return
      end
    rescue ArgumentError
      flash[:error] = "There was a problem skipping one of the pending deployment protection rules."
    rescue ActiveRecord::RecordNotFound
      flash[:error] = "Pending deployment protection rules were not found."
    end

    begin
      if gate_requests&.any?
        GateApprovalLog.skip_requests(actor: current_user, gate_requests: gate_requests, comment: comment)
        flash[:notice] = "The pending deployment protection rules have been skipped."
      else
        flash[:error] = "There are no pending deployment protection rules selected."
      end
    rescue ArgumentError
      flash[:error] = "There was a problem skipping one of the pending deployment protection rules."
    end

    redirect_to :back
  end

  private

  def ensure_can_use_environments
    render_404 unless current_repository.can_use_environments?
  end
end
