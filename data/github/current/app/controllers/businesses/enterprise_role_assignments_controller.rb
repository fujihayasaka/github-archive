# typed: strict
# frozen_string_literal: true

class Businesses::EnterpriseRoleAssignmentsController < Businesses::BusinessController
  include ReactHelper

  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :custom_enterprise_roles_enabled

  layout "layouts/react_business"

  depends_on_clusters \
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Spokes,
    only: [:index]

  sig { void }
  def index
    render_react_app(
      app_name: "enterprise-role-assignments",
      payload: { slug: this_business.slug },
      page_data: { selected_link: :enterprise_roles },
      title: "Enterprise role assignments · #{this_business.name}",
    )
  end

  private

  sig { void }
  def custom_enterprise_roles_enabled
    render_404 unless this_business.feature_enabled?(:custom_enterprise_role_feature)
  end
end
