# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/ControllersShouldHaveTests

module Stafftools::PersonalAccessTokens::GrantRequests
  class AbstractController < ::Stafftools::PersonalAccessTokens::Grantables::AbstractController
    before_action :ensure_current_grant_request_exists, except: [:index]

    private

    memoize def current_grant_request
      ProgrammaticAccessGrantRequest
        .with_target(current_target)
        .includes(:target, :grant)
        .find_by(user_programmatic_access: current_access)
    end

    def ensure_current_grant_request_exists
      render_404 unless current_grant_request
    end

    def selected_link
      "#{current_target_type.downcase}_requests"
    end

    def paginated_grant_requests
      ProgrammaticAccessGrantRequest.with_target_type_and_access(
        current_target_type, current_access
      ).includes(:target, :grant).paginate(
        page: current_page, per_page: PER_PAGE,
      )
    end
  end
end
