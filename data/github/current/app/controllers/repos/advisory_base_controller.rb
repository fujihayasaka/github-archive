# typed: true
# frozen_string_literal: true

class Repos::AdvisoryBaseController < AbstractRepositoryController
  before_action :check_feature_is_enabled

  protected

  memoize def advisory
    current_repository.repository_advisories.find_by!(ghsa_id: params[:id])
  end

  private

  def check_feature_is_enabled
    render_404 unless current_repository.advisories_enabled?
  end

  # Original authorization - checks if user can write to the advisory.
  # Does NOT check for locks. Use this for existing behavior.
  def authorize_advisory_writable
    render_404 unless advisory.writable_by?(current_user)
  end

  # Authorization that respects locks - use for editing the advisory itself.
  # Blocks non-admins when the advisory is locked.
  def authorize_advisory_editable
    unless advisory.writable_by?(current_user)
      render_404
      return
    end

    if advisory.locked_for?(current_user)
      respond_to do |format|
        format.html do
          flash[:error] = "This advisory is locked. Only repository admins can edit it."
          redirect_to gh_repository_advisory_path(advisory)
        end
        format.json do
          render json: { error: "advisory locked" }, status: :forbidden
        end
      end
    end
  end

  # Checks if user is an advisory collaborator (can view/read the advisory).
  # Use this for read-only operations like viewing partials or commenting.
  def authorize_advisory_collaborator
    render_404 unless advisory.writable_by?(current_user)
  end

  alias_method :authorize_advisory_commentable, :authorize_advisory_collaborator
end
