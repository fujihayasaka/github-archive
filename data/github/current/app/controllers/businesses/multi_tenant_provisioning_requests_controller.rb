# typed: true
# frozen_string_literal: true

class Businesses::MultiTenantProvisioningRequestsController < ApplicationController
  before_action :login_required
  before_action :dotcom_required
  before_action :non_emu_required
  before_action :digital_front_door_proxima_ff_enabled

  layout "layouts/enterprise_dfd_funnel"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:show]

  stylesheet_bundle :site
  stylesheet_bundle "business-trial"

  def show
    return render_404 unless multi_tenant_provisioning_request.present?

    render "businesses/multi_tenant_provisioning_requests/show", locals: {
      show_multi_tenant_provisioning_steps: true
    }
  end

  private

  def digital_front_door_proxima_ff_enabled
    render_404 unless current_user.feature_enabled?(:digital_front_door_proxima)
  end

  def multi_tenant_provisioning_request
    MultiTenantProvisioningRequest.find_by(subdomain: params[:subdomain], created_by: current_user)
  end

  def resource_for_conditional_access
    return self if multi_tenant_provisioning_request.nil?

    multi_tenant_provisioning_request
  end

  def target_for_conditional_access
    current_user
  end
end
