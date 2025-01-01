# typed: true
# frozen_string_literal: true
# rubocop:disable GitHub/ControllersShouldHaveTests

module Stafftools::PersonalAccessTokens::Grants
  class AbstractController < ::Stafftools::PersonalAccessTokens::Grantables::AbstractController
    before_action :ensure_current_grant_exists,  except: [:index]

    private

    memoize def current_grant
      ProgrammaticAccessGrant.with_target(current_target).find_by(
        user_programmatic_access: current_access
      )
    end

    def ensure_current_grant_exists
      render_404 unless current_grant
    end

    def paginated_grants
      ProgrammaticAccessGrant.with_target_type_and_access(
        current_target_type, current_access
      ).includes(:target).paginate(
        page: current_page, per_page: PER_PAGE,
      )
    end

    def selected_link
      current_target_type.downcase.pluralize
    end
  end
end
