# typed: true
# frozen_string_literal: true

class Marketplace::Actions::UsableIconsController < ApplicationController
  before_action :login_required

  layout false

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:index]

  MAX_RESULTS = 50

  def index
    if params[:q]
      icons = RepositoryActions::Icons::NAMES.grep(/#{Regexp.escape(params[:q])}/).first(MAX_RESULTS)
    else
      icons = RepositoryActions::Icons::NAMES.first(MAX_RESULTS)
    end

    render "marketplace/actions/usable_icons/index", formats: :html, locals: { icons: icons }
  end

  private

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def ip_allowlist_enforceable
    :no
  end

  # Opting out from external conditional access policies is handled in this method
  def external_conditional_access_policy_enforceable
    :no
  end

  def require_active_external_identity_session?
    false
  end

  def two_factor_enforceable
    :no
  end
end
