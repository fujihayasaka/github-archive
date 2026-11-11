# typed: strict
# frozen_string_literal: true

# Handles toggle switch updates for in-product messaging preferences for both
# organizations and enterprises.
#
# Called via POST by Primer::Alpha::ToggleSwitch components on profile settings
# pages. Each toggle identifies its target field via the `field` query parameter
# and sends the desired state as `value` ("1" for on, "0" for off) in the POST
# body. This is the standard Primer ToggleSwitch wire format.
#
# See: vendor/gems/.../primer_view_components-.../app/components/primer/alpha/toggle_switch.ts
class InProductTargeting::MessagingPreferencesController < ApplicationController
  include OrganizationsHelper
  include Businesses::Concerns::BusinessAccess

  before_action :login_required
  before_action :authorize_owner!
  # depends_on_clusters ApplicationRecord::InProductTargeting, only: :create

  ALLOWED_FIELDS = T.let(%w[promotion_subscribed tip_subscribed members_request_subscribed].freeze, T::Array[String])

  sig { void }
  def create
    field = params[:field].to_s
    unless ALLOWED_FIELDS.include?(field)
      head :bad_request
      return
    end

    enabled = params[:value] == "1"

    if ::InProductTargeting.domain.update_messaging_preference!(
      field:,
      enabled:,
      organization_id: organization_context? ? current_organization.id : nil,
      business_id: organization_context? ? nil : this_business.id,
    )
      head :ok
    else
      head :unprocessable_entity
    end
  end

  private

  sig { returns(T::Boolean) }
  def organization_context?
    params[:organization_id].present?
  end

  sig { void }
  def authorize_owner!
    if organization_context?
      render_404 unless current_organization&.adminable_by?(current_user)
    else
      render_404 unless this_business&.owner?(current_user)
    end
  end
end
