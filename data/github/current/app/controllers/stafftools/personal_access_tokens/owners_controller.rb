# typed: true
# frozen_string_literal: true

class Stafftools::PersonalAccessTokens::OwnersController < StafftoolsController
  include PersonalAccessTokensControllerHelper

  before_action :ensure_user_exists
  before_action :ensure_org_not_user
  before_action :ensure_feature_flag_enabled

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

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  PER_PAGE = 25

  def index
    render \
      partial: "stafftools/personal_access_tokens/owners_list",
      layout: false,
      locals: {
        selected_owner: selected_owner_in_query&.display_login,
        org_members: this_user.members
      }
  end

  private

  def ensure_feature_flag_enabled
    render_404 unless current_user.patsv2_enabled?
  end

  def selected_owner_in_query
    query = params[:q]

    return unless query.present?
    return unless (result = query.match(OWNER_REGEX))

    User.find_by_login(result[:login])
  end
end
