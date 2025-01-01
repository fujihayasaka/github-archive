# typed: true
# frozen_string_literal: true

class IpAllowlistChecksController < ApplicationController
  include IntegrationManagerHelper

  before_action :ensure_ip_allowlists_available
  before_action :login_required
  before_action :owner_required
  before_action :owner_admin_or_site_admin_required
  # Let site admins perform IP checks without performing CAP checks.
  skip_before_action :perform_conditional_access_checks, # rubocop:disable GitHub/DoNotSkipCapBeforeAction
    only: [:show],
    if: -> do
      T.bind(self, IpAllowlistChecksController)
      current_user&.site_admin?
    end

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::NotificationsEntries,
    only: [:show]

  def show
    respond_to do |format|
      format.html_fragment do
        render IpAllowlistChecks::ResultsComponent.new(
          ip: ip_from_params, owner: owner, permitting_entries: permitting_entries
        ), layout: false
      end
    end
  end

  private

  memoize def ip_from_params
    params[:ip].to_s.strip
  end

  memoize def permitting_entries
    owned_entries = IpAllowlistEntry
      .usable_for(owner)
      .active
      .matching_ip(ip_from_params)
      .order(allow_list_value: :asc)
    owned_entries + permitting_installed_app_entries
  end

  memoize def permitting_installed_app_entries
    IpAllowlistEntry
      .installed_for(owner)
      .active
      .matching_ip(ip_from_params)
      .order(allow_list_value: :asc)
  end

  memoize def owner
    case params[:owner_type].to_sym
    when :enterprise
      Business.find_by(id: params[:owner_id])
    when :organization
      Organization.find_by(id: params[:owner_id])
    when :integration
      Integration.find_by(id: params[:owner_id])
    end
  end

  def owner_required
    render_404 unless owner
  end

  def owner_admin_or_site_admin_required
    return if current_user.site_admin?
    return if owner.is_a?(Organization) && owner.adminable_by?(current_user)
    return if owner.is_a?(Business) && owner.owner?(current_user)
    return if owner.is_a?(Integration) && Apps::ManagementHelper.can_edit?(app: owner, actor: current_user)

    render_404
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access if owner.is_a?(Integration) # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    owner
  end
end
