# typed: true
# frozen_string_literal: true

class RepositoryRulesBypassRequestsController < AbstractRepositoryController
  before_action :login_required

  include ApplicationController::VerifiedFetchDependency
  include Exemptions::Evaluators

  include BypassRequestsControllerMethods

  before_action :require_user_can_write_to_repo
  before_action :ensure_user_has_edit_branch_protection, only: [:index, :bypass_request_requesters, :bypass_request_approvers]

  allow_verified_fetch only: FETCH_ENDPOINTS

  sig { override.returns(Repository) }
  protected def current_source
    current_repository
  end

  sig { override.returns(Symbol) }
  protected def selected_link
    :org_rules_bypass_requests
  end

  sig { override.returns(String) }
  protected def layout
    "layouts/settings/rules"
  end

  sig { override.returns(String) }
  protected def title
    "Settings · Bypass Requests · #{current_repository.name_with_display_owner}"
  end

  sig { override.returns(T.nilable(String)) }
  protected def base_exemption_url
    "/#{current_repository.name_with_display_owner}/exemptions/"
  end

  sig { override.void }
  def index
    return render_404 if current_repository.fork?

    super
  end

  private

  sig { void }
  def require_user_can_write_to_repo
    render_404 unless current_source.writable_by?(current_user)
  end
end
