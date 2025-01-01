# typed: true
# frozen_string_literal: true

class Settings::SessionsController < ApplicationController
  include Settings::ControllerMethods
  include OrganizationsHelper

  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :sudo_filter, only: ["mobile_revoke"]

  stylesheet_bundle :settings
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  MOBILE_DEVICE_REVOKE_REASON = "user_revoked_from_sessions_settings_page"

  def index
    render "settings/sessions/show"
  end

  def mobile_revoke # rubocop:todo GitHub/UseRestfulActions
    mobile_device = current_user.all_mobile_device_auth_keys.find { |k| k.id == params[:id].to_i }

    # if we cannot find the associated mobile device, there's nothing to revoke
    if mobile_device.nil?
      flash[:error] = "Cannot find the associated mobile device."
      GitHub.dogstats.increment("mobile_session.revoke", tags: ["status:failure", "reason:device_not_found"])
      return redirect_to settings_sessions_path
    end

    # if a device has the same device_name, device_model and device_os
    # they show up as a single record in the UI
    # we should revoke all of them since the user doesn't know the difference
    similar_devices = get_similar_devices(mobile_device)
    all_devices = [mobile_device] + similar_devices
    all_device_ids = all_devices.collect { |device| device.id }

    # revoke in authnd
    result = current_user.revoke_mobile_device_keys_by_ids(current_user, all_device_ids, MOBILE_DEVICE_REVOKE_REASON)
    if result == :RESULT_SUCCESS
      # if we successfully revoked the device keys in authnd, now we can destroy the corresponding oauth access rows
      destroy_mobile_device_oauth_accesses(all_devices, entry_point: :sessions_controller_mobile_revoke_by_ids)
      GitHub.dogstats.increment("mobile_session.revoke", tags: ["status:success", "reason:by_ids"])
    else
      GitHub.dogstats.increment("mobile_session.revoke", tags: ["status:failure", "reason:by_ids", "result:#{result}"])
      flash[:error] = "Could not revoke the mobile device. Please try again."
    end
    redirect_to settings_sessions_path
  end

  private

  # Method to get similar devices based on device_name, device_model and device_os to the comparable device
  # Returns a list of similar devices (the returned list DOES NOT include the comparable_device given)
  def get_similar_devices(comparable_device)
    current_user.all_mobile_device_auth_keys.select do |key|
      key.device_name == comparable_device.device_name &&
        key.device_model == comparable_device.device_model &&
        key.device_os == comparable_device.device_os &&
        key.id != comparable_device.id
    end
  end

  # Method to destroy the oauth access rows associated with the given devices
  def destroy_mobile_device_oauth_accesses(devices, entry_point:)
    access_ids = devices.collect { |device| device.oauth_access_id }
    return unless access_ids.count > 0
    oauth_accesses = current_user.oauth_accesses.where(id: access_ids)
    oauth_accesses.each do |oauth_access|
      oauth_access.destroy_with_explanation(:web_user, entry_point: entry_point)
      GitHub.dogstats.increment("mobile_session.oauth_access.revoke", tags: ["status:success"])
    end
  end
end
