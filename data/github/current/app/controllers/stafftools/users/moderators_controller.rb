# typed: true
# frozen_string_literal: true

class Stafftools::Users::ModeratorsController < StafftoolsController
  before_action :ensure_org_not_user
  before_action :ensure_moderation_features_enabled
  before_action :ensure_user_exists

  layout "layouts/stafftools/organization/security"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    render "stafftools/users/moderators/index", locals: { moderators: this_user.moderators }
  end

  private

  def ensure_moderation_features_enabled
    return render_404 unless GitHub.organization_moderators_enabled?
  end
end
