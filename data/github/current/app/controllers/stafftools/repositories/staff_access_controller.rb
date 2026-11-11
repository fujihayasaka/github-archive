# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::StaffAccessController < Stafftools::RepositoriesController

  before_action :ensure_repo_exists

  # Unlock a user's repository for two hours
  #
  # Requires `can-unlock-repos-with-owners-permission` role
  # Requires an active StaffAccessGrant unless in Enterprise
  # params[:reason] can be nil in Dotcom (reason will be taken from the active grant)
  def staff_unlock # rubocop:todo GitHub/UseRestfulActions
    reason = params[:reason]
    if GitHub.enterprise? && reason.blank?
      # Confirm the reason has been given.
      flash[:error] = "You must provide a reason for this unlock."
      redirect_to :back
    else
      # Do the actual unlocking
      if unlock = current_user.unlock_repository(current_repository, reason)
        instrument("repo.staff_unlock",
                    current_repository.owner.event_prefix => current_repository.owner,
                    :repo => current_repository,
                    :reason => unlock.reason)
        flash[:notice] = "#{current_repository.name_with_owner} has been unlocked for #{current_user}."
      else
        instrument("repo.failed_staff_unlock",
                    current_repository.owner.event_prefix => current_repository.owner,
                    :repo => current_repository)
        flash[:notice] = "The repo has not been unlocked. There is no valid staff access grant or you do not have permission."
      end

      redirect_to :back
    end
  end

  # Unlock the repository without notifying the user.
  # This should only be used for security & legal purposes.
  # Requires `can-unlock-repos-without-owners-permission` stafftools role.
  def override_unlock # rubocop:todo GitHub/UseRestfulActions
    reason = params[:reason]

    if reason.blank?
      flash[:error] = "You must provide a reason for this unlock."
      redirect_to :back
    else
      current_repository.staff_access_grants.create(granted_by: current_user, reason: reason)

      if unlock = current_user.unlock_repository(current_repository, reason)
        instrument("repo.override_unlock",
                    current_repository.owner.event_prefix => current_repository.owner,
                    :repo => current_repository,
                    :reason => unlock.reason)
        flash[:notice] = "#{current_repository.name_with_owner} has been unlocked for #{current_user}."
      end

      redirect_to gh_security_stafftools_repository_path(current_repository)
    end
  end

  def cancel_unlock # rubocop:todo GitHub/UseRestfulActions
    unlock = RepositoryUnlock.with_staffer_and_repository(current_user, current_repository)
    if unlock && unlock.active?
      unlock.revoke(current_user)
      flash[:notice] = "Unlock for #{current_repository.name_with_owner} canceled."
    else
      flash[:error] = "#{current_repository.name_with_owner} is not unlocked."
    end

    redirect_to gh_security_stafftools_repository_path(current_repository)
  end

  def request_access # rubocop:todo GitHub/UseRestfulActions
    return redirect_to gh_security_stafftools_repository_path(current_repository) if GitHub.enterprise?

    reason = params[:reason]
    admins = params[:admins]

    if reason.blank?
      flash[:error] = "You must provide a reason for this unlock."
    elsif admins.blank?
      flash[:error] = "You must choose at least one admin from whom to request access."
    else
      request = current_repository.request_staff_access(current_user, reason)
      StaffAccessMailer.repo_access_requested(request, admins).deliver_later

      flash[:notice] = "Access to #{current_repository.name_with_owner} has been requested for #{current_user}."
    end

    redirect_to gh_security_stafftools_repository_path(current_repository)
  end

  def cancel_access_request # rubocop:todo GitHub/UseRestfulActions
    current_request = current_repository.active_staff_access_request # TODO: this should be passed in as a param
    current_request.cancel(current_user) if current_request
    redirect_to gh_security_stafftools_repository_path(current_repository)
  end
end
