# typed: true
# frozen_string_literal: true

class Stafftools::AuthenticatedDevicesController < StafftoolsController
  before_action :sudo_filter

  before_action :ensure_user_exists

  def verify # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless this_user&.user?

    if device = this_user.authenticated_devices.find_by_device_id(params[:device_id])
      device.verify!
      flash[:notice] = %("#{device.display_name}" with ID #{params[:device_id]} has been verified for #{this_user})
      this_user.instrument_unverified_device(:device_verification_success, device, actor: current_user, reason: :staff_verification)
    else
      flash[:error] = "#{this_user} has not yet used device #{params[:device_id]}"
    end

    redirect_to :back
  end

  def unverify # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless this_user&.user?

    device = this_user.authenticated_devices.find_by_device_id(params[:device_id])
    flash[:error] = "#{this_user} has not yet used device #{params[:device_id]}" unless device
    flash[:error] ||= "#{this_user}'s device is already unverified #{params[:device_id]}" if device&.unverified?
    flash[:error] ||= "Could not unverify device: #{device.errors.to_sentence}" unless device&.unverify

    unless flash[:error]
      flash[:notice] = %(Successfully unverified "#{device.display_name}" with ID #{params[:device_id]} for #{this_user})
      this_user.instrument_unverified_device(:device_unverification, device, actor: current_user, reason: :staff_unverification)
    end

    redirect_to :back
  end
end
