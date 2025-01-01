# typed: true
# frozen_string_literal: true

class AccountController < ApplicationController
  before_action :login_required
  around_action :select_write_database, only: [:accept_repository_transfer_request]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Notify,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Permissions,
    ApplicationRecord::Iam,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Pages,
    ApplicationRecord::RepositoriesPushes,
    only: [:accept_repository_transfer_request]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:accept_repository_transfer_request], optional: true

  # The following actions do not require conditional access checks:
  #
  # leave_repo                          - Does not access protected
  #                                       organization resources
  # read broadcast                      - Does not access protected
  #                                       organization resources
  ACTIONS_EXCLUDED_FROM_CAP_CHECKS = %w(read_broadcast leave_repo)

  def accept_repository_transfer_request # rubocop:todo GitHub/UseRestfulActions
    case xfer
    when :expired_token
      error = "Oops! That repository transfer has expired."
    when nil
      error = "Oops! That repository transfer request is invalid. Did you copy the URL correctly?"
    end

    if error
      flash[:error] = error
      return redirect_to "/"
    end

    GlobalInstrumenter.instrument("repository.transfer_email", {
      repository: xfer.repository,
      email_reason: "transfer_approved",
      user: current_user,
      target_id: xfer.target_id,
    })

    begin
      xfer.finish current_user
    rescue ActiveRecord::RecordInvalid => e
      Failbot.report_user_error e, repository_transfer_id: xfer.id
      flash[:error] = "Sorry, this repository transfer can’t be finished."

      return redirect_to "/"
    end

    flash[:notice] = "Moving repository to #{current_user.display_login}/#{xfer.new_name}. This may take a few minutes."
    redirect_to "/"
  end

  def read_broadcast # rubocop:todo GitHub/UseRestfulActions
    current_user.update(last_read_broadcast_id: params[:id])
    if request.xhr?
      head :ok
    else
      redirect_to :back
    end
  end

  # Allows a user to remove themselves as a collaborator
  # from a repository.
  def leave_repo # rubocop:todo GitHub/UseRestfulActions
    repo = Repository.where(id: params[:repo]).first
    if repo && repo.member?(current_user)
      repo.remove_member(current_user, current_user)
    end

    if request.xhr?
      head 200
    else
      flash[:notice] = "Your collaborator access to the repository was successfully removed."
      redirect_to :back
    end
  end

  private

  memoize def xfer
    RepositoryTransfer.from params[:token]
  end

  def ip_allowlist_enforceable
    return :no if ACTIONS_EXCLUDED_FROM_CAP_CHECKS.include?(action_name)
    super
  end

  # Opt-out of external CAP policy enforcement
  def external_conditional_access_policy_enforceable
    return :no if ACTIONS_EXCLUDED_FROM_CAP_CHECKS.include?(action_name)
    super
  end

  def require_active_external_identity_session?
    return false if ACTIONS_EXCLUDED_FROM_CAP_CHECKS.include?(action_name)
    true
  end

  def two_factor_enforceable
    return :no if ACTIONS_EXCLUDED_FROM_CAP_CHECKS.include?(action_name)
    :yes
  end

  def target_for_conditional_access
    if action_name == "accept_repository_transfer_request" && !xfer.is_a?(Symbol) && xfer&.target&.present?
      return xfer.target
    end
    # cap_bypass:to_fix with ACTIONS_EXCLUDED_FROM_CAP_CHECKS it looks like CAP always gets bypassed
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
