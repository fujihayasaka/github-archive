# typed: true
# frozen_string_literal: true

class Stafftools::Users::UndeletesController < StafftoolsController
  before_action :ensure_org_does_not_belong_to_deleted_business
  before_action :ensure_user_deletion_failed

  def create
    return render_404 unless this_user.present?

    msg = this_user.organization? && this_user.soft_deleted? ? "restored" : "marked as not deleted"
    if this_user.mark_not_deleted(actor: current_user)
      flash[:notice] = "#{this_user} was successfully #{msg}."
    else
      flash[:error] = "#{this_user} could not be marked as not deleted."
    end
    redirect_to stafftools_user_overview_path(this_user)
  end

  private

  def ensure_user_deletion_failed
    delete_job_status = UserDeleteJob.status(this_user.id)
    suitable_user = \
      (this_user.deleted? || this_user.soft_deleted?) &&
      (delete_job_status.nil? || delete_job_status.error?)
    render_404 unless suitable_user
  end

  def ensure_org_does_not_belong_to_deleted_business
    return unless this_user.organization?

    if this_user.belongs_to_a_soft_deleted_business?
      flash[:error] = "This organization is part of a deleted enterprise. It cannot be restored."
      redirect_to stafftools_user_overview_path(this_user)
    end
  end
end
