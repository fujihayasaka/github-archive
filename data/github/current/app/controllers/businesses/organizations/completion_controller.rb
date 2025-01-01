# typed: true
# frozen_string_literal: true

class Businesses::Organizations::CompletionController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required
  before_action :require_current_organization

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: %i(show)

  depends_on_clusters ApplicationRecord::Copilot, only: [:show], optional: true

  def show
    # presence of this flash key will trigger the banner, only show for orgs created in the last day
    flash[:show_new_business_org_message] = "true" if current_organization.created_at > 1.day.ago
    redirect_to user_path(current_organization)
  end
end
