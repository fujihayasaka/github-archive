# typed: strict
# frozen_string_literal: true

class Stafftools::RepositoryRulesBypassRequestsController < StafftoolsController

  before_action :disallow_forks, only: [:index]

  include ApplicationController::VerifiedFetchDependency
  include Exemptions::Evaluators
  include BypassRequestsControllerMethods

  depends_on_clusters ApplicationRecord::Ballast

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
    "layouts/stafftools/repository/overview"
  end

  sig { override.returns(String) }
  protected def title
    "Settings · Bypass Requests · #{current_repository.name_with_display_owner}"
  end

  sig { override.returns(T::Boolean) }
  protected def stafftools?
    true
  end

  sig { override.returns(T.nilable(String)) }
  protected def base_exemption_url
    "/stafftools/repositories/#{current_repository.name_with_display_owner}/exemptions/"
  end

  sig { void }
  private def disallow_forks
    render_404 if current_repository.fork?
  end

end
