# typed: true
# frozen_string_literal: true

class Businesses::AvailableLicensesController < Businesses::BusinessController
  include BusinessesHelper

  before_action :login_required
  before_action :business_owner_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: %i(show)

  def show
    respond_to do |format|
      format.html do
        render Businesses::AvailableLicensesComponent.new(
          business: this_business,
          available_licenses: this_business.available_invitable_licenses
        ), layout: false
      end
    end
  end
end
