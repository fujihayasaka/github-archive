# typed: true
# frozen_string_literal: true
# rubocop:disable GitHub/ControllersShouldHaveTests

module Stafftools::PersonalAccessTokens::Grantables
  class AbstractController < StafftoolsController
    PER_PAGE = 25

    before_action :ensure_user_exists
    before_action :ensure_feature_flag_enabled

    before_action :ensure_current_access_exists
    before_action :ensure_current_target_exists, except: [:index]

    helper_method :current_access,
                  :current_target_type,
                  :gh_stafftools_user_personal_access_token_grant_path,
                  :gh_stafftools_user_personal_access_token_grant_request_path,
                  :selected_link

    layout "layouts/stafftools/user/personal_access_token"

    private

    memoize def current_access
      ProgrammaticAccess.for(this_user).find_by(id: params[:personal_access_token_id])
    end

    memoize def current_target
      User.find_by(login: params[:id])
    end

    def current_target_type
      raise NotImplementedError, "needs to implemented by child controller"
    end

    def ensure_current_access_exists
      render_404 unless current_access
    end

    def ensure_current_target_exists
      render_404 unless current_target
    end

    def ensure_feature_flag_enabled
      render_404 unless current_user.patsv2_enabled?
    end

    def gh_stafftools_user_personal_access_token_grant_path(user, access, grant)
      case grant.target
      when Organization
        stafftools_user_personal_access_token_organization_path(user, access, grant.target)
      when User
        stafftools_user_personal_access_token_user_path(user, access, grant.target)
      end
    end

    def gh_stafftools_user_personal_access_token_grant_request_path(user, access, grant_request)
      case grant_request.target
      when Organization
        request_stafftools_user_personal_access_token_organization_path(user, access, grant_request.target)
      when User
        request_stafftools_user_personal_access_token_user_path(user, access, grant_request.target)
      end
    end

    def selected_link
      raise NotImplementedError, "needs to implemented by child controller"
    end
  end
end
