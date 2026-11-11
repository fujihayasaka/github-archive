# typed: false
# frozen_string_literal: true

class AppIdenticonsController < ApplicationController

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:show]

  def show
    id_or_slug = params[:id]
    return head(:not_found) unless id_or_slug.present?

    app = case params[:type]
    when OauthApplication::IDENTICON_TYPE
      OauthApplication.find_by_id(id_or_slug.to_i)
    when Integration::IDENTICON_TYPE
      Integration.find_by(slug: id_or_slug)
    end
    return head(:not_found) unless app

    headers["Cache-Control"] = "public"
    respond_to do |format|
      format.svg do
        render "avatars/app_identicon", layout: false, locals: { identicon: app.identicon }
      end
    end
  end

  private

  # App identicons are public

  # Avatars and identicons are currently public and there's not need to CAP bypass. However, this might change in the
  # future, as there's already an ongoing investigattion to make avatars and identicons private for EMU users.
  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def ip_allowlist_enforceable
    :no
  end

  # If avatars and identicons become private for EMU users, we might need to enforce this policy for this controller.
  # Currently returning :no to be consistent with the IP allowlist policy.
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
