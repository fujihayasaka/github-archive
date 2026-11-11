# typed: true
# frozen_string_literal: true

class Stafftools::PersonalAccessTokens::GrantRequests::PendingApprovalsController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  depends_on_clusters ApplicationRecord::Ballast,
                      ApplicationRecord::Billing,
                      ApplicationRecord::Collab,
                      ApplicationRecord::IamAbilities,
                      ApplicationRecord::IssuesPullRequests,
                      ApplicationRecord::Mysql1,
                      ApplicationRecord::Mysql2,
                      ApplicationRecord::Mysql5,
                      ApplicationRecord::NotificationsEntries,
                      ApplicationRecord::Permissions,
                      ApplicationRecord::Repositories,
                      ApplicationRecord::Configurations

  depends_on_clusters ApplicationRecord::Copilot,
                      only: [:index],
                      optional: true

  before_action :ensure_user_exists
  before_action :ensure_org_not_user
  before_action :ensure_feature_flag_enabled

  PER_PAGE = 25

  def index
    paginated_requests = ProgrammaticAccessGrantRequest
      .with_target(this_user)
      .includes(user_programmatic_access: :owner)
      .paginate(page: current_page, per_page: PER_PAGE)

    render "stafftools/personal_access_tokens/grant_requests/pending_approval",
      layout: security_layout,
      locals: { grant_requests: paginated_requests }
  end

  private

  def ensure_feature_flag_enabled
    render_404 unless current_user.patsv2_enabled?
  end
end
