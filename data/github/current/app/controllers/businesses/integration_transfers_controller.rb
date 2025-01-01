# typed: true
# frozen_string_literal: true

class Businesses::IntegrationTransfersController < Businesses::BusinessController

  before_action :this_business_required

  include IntegrationTransfersControllerMethods

  before_action :business_admin_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:show]

  private

  # Implemented for IntegrationTransfersControllerMethods
  def current_context
    this_business
  end

  # Internal: This before_action renders a standard 404 page if `this_business` is nil.
  #
  # Returns nothing.
  def this_business_required
    render_404 if this_business.nil?
  end

  def business_admin_required
    render_404 unless this_business.adminable_by?(current_user)
  end
end
