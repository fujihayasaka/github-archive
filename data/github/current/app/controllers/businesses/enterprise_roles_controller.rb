# typed: true
# frozen_string_literal: true

class Businesses::EnterpriseRolesController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :custom_enterprise_roles_enabled

  depends_on_clusters \
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    only: [:index, :new]

  def index
    render "businesses/enterprise_roles/index", locals: { business: this_business }
  end

  def new
    render "businesses/enterprise_roles/new", locals: { business: this_business }
  end

  private

  def custom_enterprise_roles_enabled
    render_404 unless this_business.feature_enabled?(:custom_enterprise_role_feature)
  end
end
