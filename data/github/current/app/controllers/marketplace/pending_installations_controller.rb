# typed: true
# frozen_string_literal: true

class Marketplace::PendingInstallationsController < ApplicationController

  before_action :login_required
  before_action :marketplace_required

  layout "layouts/marketplace"
  stylesheet_bundle :marketplace

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    pending_installations = current_user.
      pending_marketplace_installations(only_notice_triggered: false).
      preload(:subscribable).
      first(25)

    render "marketplace/pending_installations/index", locals: { pending_installations: pending_installations }
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
