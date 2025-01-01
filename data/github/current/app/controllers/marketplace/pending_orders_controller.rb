# typed: true
# frozen_string_literal: true

class Marketplace::PendingOrdersController < ApplicationController

  before_action :marketplace_required
  before_action :login_required

  layout "layouts/marketplace"
  stylesheet_bundle :marketplace

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    previews = current_user.marketplace_order_previews
                           .with_valid_listing_data
                           .order(:viewed_at)
                           .limit(50)

    render "marketplace/pending_orders/index", locals: { order_previews: previews }
  end

  private

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def ip_allowlist_enforceable
    :no
  end

  def require_active_external_identity_session?
    false
  end

  def two_factor_enforceable
    :no
  end
end
