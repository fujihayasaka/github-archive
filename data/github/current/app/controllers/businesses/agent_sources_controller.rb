# typed: true
# frozen_string_literal: true

class Businesses::AgentSourcesController < Businesses::BusinessController
  include AgentSourcesControllerMethods

  before_action :this_business_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Lodge,
    only: [:show, :new]

  javascript_bundle :settings
  stylesheet_bundle :settings

  private

  def current_context
    this_business
  end

  def this_business_required
    render_404 if this_business.nil?
  end
end
