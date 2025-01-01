# typed: true
# frozen_string_literal: true

require "resolv"

class Stafftools::LockedIpController < StafftoolsController

  before_action :verify_ip_address
  before_action :ensure_lockouts_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  IP_REGEX = Regexp.union(
    Resolv::IPv4::Regex,
    Resolv::IPv6::Regex,
  )

  def index
    @query_string = params[:ip_address]
    render "stafftools/locked_ip/index"
  end

  # Removes a lockout due to rate limiting authentication attempts.
  def destroy
    AuthenticationLimit.clear_data(ip: @ip_address, web_ip: @ip_address)
    flash[:notice] = "#{@ip_address} unlocked"

    redirect_to :back
  end

  def whitelist # rubocop:todo GitHub/UseRestfulActions
    expires_unit = params[:expires_unit]
    unless %w(minutes hours days months years).include? expires_unit
      flash[:error] = "Invalid expires unit"
      return redirect_to :back
    end

    expires_value = params[:expires_value].to_i
    unless expires_value > 0
      flash[:error] = "Invalid expires value"
      return redirect_to :back
    end

    expires = expires_value.send(expires_unit).from_now

    if entry = AuthenticationLimitWhitelistEntry.find_by(metric: "ip", value: @ip_address)
      entry.update(
        metric: "ip",
        value: @ip_address,
        creator: current_user,
        note: params[:note],
        expires_at: expires,
      )
    else
      entry = AuthenticationLimitWhitelistEntry.create(
        metric: "ip",
        value: @ip_address,
        creator: current_user,
        note: params[:note],
        expires_at: expires,
      )
    end

    unless entry.valid?
      flash[:error] = entry.errors.full_messages.to_sentence
    end
    redirect_to :back
  end

  def unwhitelist # rubocop:todo GitHub/UseRestfulActions
    if entry = AuthenticationLimitWhitelistEntry.find_by(metric: "ip", value: @ip_address)
      entry.destroy
      flash[:notice] = "Removed whitelist entry for #{entry.value}"
    end
    redirect_to :back
  end

  private

  def verify_ip_address
    @ip_address = params[:ip_address] if params[:ip_address] =~ IP_REGEX
    flash[:error] = "You must provide a valid IP address" unless @ip_address
  end

  def ensure_lockouts_enabled
    render_404 unless GitHub.lockouts_enabled?
  end
end
