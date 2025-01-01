# typed: true
# frozen_string_literal: true

class Stafftools::PersonalAccessTokensController < StafftoolsController
  include PersonalAccessTokensControllerHelper
  include Stafftools::Users::ControllerLayoutMethods

  before_action :ensure_user_exists
  before_action :ensure_feature_flag_enabled
  before_action :ensure_current_access_exists, except: [:index]

  layout "layouts/stafftools/user/personal_access_token", except: [:index]

  helper_method :current_access

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Permissions,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Permissions,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Permissions,
    ApplicationRecord::Collab,
    only: [:expiration]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show],
    optional: true

  PER_PAGE = 25

  def index
    accesses =
      if this_user.organization?
        accesses_on_org = ProgrammaticAccess.granted_on(this_user)
        params[:q].present? ? accesses_on_org.where(owner: selected_owner_in_query) : accesses_on_org
      else
        ProgrammaticAccess.for(this_user)
      end

    render "stafftools/personal_access_tokens/index", layout: security_layout, locals: {
      accesses: accesses.paginate(page: current_page, per_page: PER_PAGE)
    }
  end

  def show
    render "stafftools/personal_access_tokens/show", locals: { access: current_access }
  end

  def compare # rubocop:todo GitHub/UseRestfulActions
    token = params[:compromised_token]

    req = ::Authnd::Proto::AuthenticateRequest::new(
      credentials: ::Authnd::Proto::Credentials::access_token(token))
    resp = ::GitHub::Authnd.authenticator_for("github/authnd").authenticate(req)

    unless resp.success?
      flash[:notice] = "Token does not exist"
      return redirect_to stafftools_user_personal_access_token_path(this_user)
    end

    found_access = ProgrammaticAccess.find(resp.attributes["access.id"])

    if current_access == found_access
      flash[:error] = "Compromised token matched, you should revoke this token."
    else
      flash[:notice] = "Token exists but does not belong to this access"
    end

    redirect_to stafftools_user_personal_access_token_path(this_user)
  end

  def destroy
    result = ProgrammaticAccess.destroy(current_access, :site_admin)

    if result.success?
      flash[:notice] = "Personal access token '#{current_access.name}' revoked"
    else
      flash[:error] = "The token was unable to be deleted: #{result.error}"
    end

    redirect_to stafftools_user_personal_access_tokens_path(this_user)
  end

  def expiration # rubocop:todo GitHub/UseRestfulActions
    expiration_result = ProgrammaticAccessToken.expiration_for(current_access)
    return head :service_unavailable if expiration_result.failed?

    render PersonalAccessTokens::ExpirationInfoComponent.new(
      expiration_time: expiration_result.value
    ), layout: false
  end

  private

  memoize def current_access
    ProgrammaticAccess.for(this_user).find_by(id: params[:id])
  end

  def ensure_feature_flag_enabled
    render_404 unless current_user.patsv2_enabled?
  end

  def ensure_current_access_exists
    render_404 unless current_access
  end

  def selected_owner_in_query
    query = params[:q]

    return unless query.present?
    return unless (result = query.match(OWNER_REGEX))

    User.find_by_login(result[:login])
  end
end
