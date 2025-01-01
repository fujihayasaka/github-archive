# typed: true
# frozen_string_literal: true

class Repos::RestoreController < ApplicationController
  before_action :login_required, :dotcom_required, :perform_conditional_access_checks, :safe_actor

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Ballast,
    only: [:restore_status]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Ballast,
    only: [:restore_partial]

  def restore # rubocop:todo GitHub/UseRestfulActions
    if safe_repo
      Repository.restore(params[:id].to_i, actor: current_user, synchronous: false)
    elsif !repo&.errors&.any?
      return render_404
    end
    respond_to do |format|
      format.html do
        if request.xhr?
          if repo&.errors&.any?
            render partial: "settings/repo_restore_error", locals: { error: repo.errors.first.message }
          else
            render partial: "settings/repo_restoring", locals: { repo_id: params[:id] }
          end
        else
          redirect_to :back
        end
      end
    end
  end

  def restore_partial # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "settings/repo_restoring", locals: { repo_id: params[:id] }
      end
    end
  end

  def restore_status # rubocop:todo GitHub/UseRestfulActions
    status = Restoration::RepositoryRestoreStatus.for(repository_id: params[:id])
    render html: status.safe_message, status: status.status
    status.reset_message_if_finished
  end

  private

  def repo # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @repo ||= Repository.where(id: params[:id], active: nil).network_safe_restoreable.first
  end

  # In this case we need to be able to find the Live repository if
  # The restore job has completed.
  # Checking for the `Repository` in `owner` allows us to return a "Done!" status for repositories that have been restored into the Repository table.
  def owner # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @owner if defined?(@owner)
    target_repo = repo.presence || Repository.where(id: params[:id]).first
    @owner = User.find_by(id: target_repo&.owner_id)
  end

  # In this case we want to return false if
  # - There is already a a restore job running for this respond_to
  # - safe_to_restore checks to see if the repo was deleted more
  #   than an hour ago
  # - We only show staff deletedd repos to staff actors
  def safe_repo
    return false unless repo.present?

    # check for any real restore blockers
    return false if !Repository.can_restore?(repo)

    # don't restore if a restore job is already running
    status = Restoration::RepositoryRestoreStatus.for(repository_id: repo.id)
    return false if status.message.present?

    # I think this is unnecessary, it's checking the repo deletion date was between 1 hour and 90 days ago.
    return false unless repo.safe_to_restore
    return false if repo.deleted_by_staff? && !current_user.site_admin?

    true
  end

  # Here we check to see if the owner is present for the newly restored Repository
  # if the owner exists, we then check to see if the
  # owner is the current user or if the owner is an admin of the targeted org
  def safe_actor
    return render_404 unless owner.present?
    render_404 unless owner.can_restore_repository?(current_user)
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless owner # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    owner
  end
end
