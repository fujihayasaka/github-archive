# typed: true
# frozen_string_literal: true

class Settings::MeteredExportsController < ApplicationController
  include BillingSettingsHelper
  include OrganizationsHelper

  before_action :ensure_billing_enabled
  before_action :login_required
  before_action :ensure_target_is_billable

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    export = target.metered_usage_exports.find(params[:id])

    redirect_to export.generate_expiring_url
  end

  private

  def target_for_conditional_access
    # CAP is not needed if there is no target. We'd 404 in that case.
    return :no_target_for_conditional_access unless target # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    target
  end

  def target # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @target ||= target!
  end

  def target!
    if params[:target] == "organization"
      org = current_organization_for_member_or_billing
      if org && org.billing_manageable_by?(current_user)
        org
      end
    else
      current_user
    end
  end

  def ensure_target_is_billable
    render_404 unless target&.billable?
  end
end
