# typed: true
# frozen_string_literal: true

class Businesses::BillingSettings::LfsUsageController < Businesses::BusinessController
  before_action :ensure_billing_enabled
  before_action :business_access_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:show]

  def show
    view = Businesses::BillingSettings::ShowView.new(current_user: current_user, business: this_business)
    render partial: "businesses/billing_settings/lfs_usage", locals: { view: view }
  end
end
