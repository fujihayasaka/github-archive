# typed: true
# frozen_string_literal: true

class IpAllowlistEntriesController < ApplicationController
  include IntegrationManagerHelper

  before_action :ensure_ip_allowlists_available
  before_action :login_required
  before_action :find_owner!
  before_action :owner_admin_required
  before_action :find_entry!, only: %i(edit update destroy)
  before_action :sudo_filter, except: %i(new edit)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:new]

  def new
    render "ip_allowlist_entries/form", locals: {
      entry: owner.ip_allowlist_entries.build,
    }
  end

  def create
    entry = owner.ip_allowlist_entries.new(entry_params)
    entry.actor_ip = request.remote_ip
    if entry.save
      flash[:notice] = "IP allow list entry created. IP allow list modifications can take a few minutes to go into effect."
      redirect_to owner_security_settings_path
    else
      flash[:error] = flash_error_message("Failed to create IP allow list entry.", entry)
      render "ip_allowlist_entries/form", locals: { entry: entry }
    end
  end

  def edit
    render "ip_allowlist_entries/form", locals: { entry: @entry }
  end

  def update
    @entry.actor_ip = request.remote_ip
    if @entry.update entry_params
      flash[:notice] = "IP allow list entry updated. IP allow list modifications can take a few minutes to go into effect."
      redirect_to owner_security_settings_path
    else
      flash[:error] = flash_error_message("Failed to update IP allow list entry.", @entry)
      render "ip_allowlist_entries/form", locals: { entry: @entry }
    end
  end

  def destroy
    @entry.actor_ip = request.remote_ip
    if @entry.destroy
      flash[:notice] = "IP allow list entry deleted. IP allow list modifications can take a few minutes to go into effect."
    else
      flash[:error] = flash_error_message("Failed to delete IP allow list entry.", @entry)
    end
    redirect_to owner_security_settings_path
  end

  private

  def flash_error_message(error, entry)
    extra = entry.errors[:base].blank? ? "" : " #{entry.errors[:base].to_sentence}."
    "#{error}#{extra}"
  end

  # Path to owner's security settings page.
  def owner_security_settings_path
    case owner
    when Organization
      settings_org_security_path(owner.display_login)
    when Business
      settings_security_enterprise_path(owner.slug)
    when Integration
      gh_settings_app_path(owner)
    end
  end
  helper_method :owner_security_settings_path

  # Path to owner's IP allow list entries page.
  def ip_allowlist_entries_path
    case owner
    when Organization
      organization_ip_allowlist_entries_path(owner)
    when Business
      enterprise_ip_allowlist_entries_path(owner)
    when Integration
      if owner.owner.organization?
        settings_org_apps_ip_allowlist_entries_path(owner.owner, owner)
      else
        settings_user_apps_ip_allowlist_entries_path(owner)
      end
    end
  end
  helper_method :ip_allowlist_entries_path

  # Before action that checks if owner is adminable by current user.
  def owner_admin_required
    return if owner.is_a?(Organization) && owner.adminable_by?(current_user)
    return if owner.is_a?(Business) && owner.owner?(current_user)
    return if owner.is_a?(Integration) && manages_integration?(user: current_user, integration: owner)

    render_404
  end

  # Before action that finds the IP allow list entry we're working with by ID.
  def find_entry!
    raise ActiveRecord::RecordNotFound if entry_id_param.nil?
    @entry = owner.ip_allowlist_entries.find_by!(id: entry_id_param)
  end

  def owner # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @owner if defined?(@owner)

    @owner = if integration_slug_param.present?
      Integration.find_by!(slug: integration_slug_param)
    elsif organization_login_param.present?
      Organization.find_by!(login: organization_login_param)
    elsif business_slug_param.present?
      Business.find_by!(slug: business_slug_param)
    end
  end

  def find_owner!
    raise ActiveRecord::RecordNotFound if owner.nil?

    owner
  end

  def tenant_verification_enforceable
    return :no if owner.is_a?(Integration)
    :yes
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access if owner.is_a?(Integration) # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    owner
  end

  def entry_params
    params.require(:ip_allowlist_entry).permit(
      :allow_list_value, :name, :active
    )
  end

  def business_slug_param
    params[:slug].presence&.to_s
  end

  def organization_login_param
    params[:organization_id].presence&.to_s
  end

  def integration_slug_param
    params[:integration_id].presence&.to_s
  end

  def entry_id_param
    params[:id].presence&.to_i
  end

  memoize def this_business
    slug = params[:enterprise_slug] || params[:slug]
    ::Business.find_by(slug: slug)
  end
end
