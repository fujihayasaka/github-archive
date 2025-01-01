# typed: true
# frozen_string_literal: true

class Stafftools::CopilotBulkBlocksController < StafftoolsController
  include CopilotBlockHelper

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    only: [:index]

  before_action :dotcom_required

  def index
    render "stafftools/copilot_bulk_blocks/index"
  end

  def block_organization # rubocop:todo GitHub/UseRestfulActions
    organization = Organization.find(params[:user_id])
    user_ids_with_seats = Copilot::Seat.for_owner(organization).pluck(:assigned_user_id)

    admins = organization.admins
    non_admins = organization.members - admins
    # We only want to block non-admins if they have seats. Admins are considered guilty regardless
    non_admins = non_admins.select { |u| user_ids_with_seats.include?(u.id) }

    reason = prefix_reason(params[:reason], params[:block_option])

    admin_reason = "#{reason}. User was an admin of the abusive organization #{organization.display_login}."
    admins.each do |u|
      Copilot::User.new(u).administrative_block!(
        current_user,
        admin_reason,
        skip_hammy_check: false,
        send_block_email: admin_reason.start_with?(WARN_VIA_SUPPORT),
        superban: false,
      )
    end

    non_admin_reason = "#{reason}. User was a member of the abusive organization #{organization.display_login}."
    non_admins.each do |u|
      Copilot::User.new(u).administrative_block!(
        current_user,
        non_admin_reason,
        skip_hammy_check: false,
        send_block_email: non_admin_reason.start_with?(WARN_VIA_SUPPORT),
        superban: false,
      )
    end

    # Disable payment method if any, and trigger billing lock
    if !organization.payment_method.nil? && admin_reason.start_with?(SUPERBAN)
      Billing::Public.blocklist_payment_method(
        account: organization,
        payment_method: organization.payment_method,
        reason: reason,
        consequence: BlacklistedPaymentMethod::Consequence::BillingLocked, # rubocop:disable Naming/InclusiveLanguage
        actor: current_user,
      )
    end

    flash[:notice] = "Blocked #{admins.count} admins and #{non_admins.count} members"
    redirect_to stafftools_user_copilot_settings_path(organization.display_login)
  end

  def create
    reason = prefix_reason(params[:reason], params[:block_option])
    logins = params[:logins].split(/[,\s]+/) # support both comma and space-delimited strings

    users = User.where(login: logins)
    logins_without_users = logins - users.map(&:login)

    if logins_without_users.any?
      flash[:error] = "Could not find users with logins: #{logins_without_users.join(", ")}"
    end

    users.each do |u|
      Copilot::User.new(u).administrative_block!(
        current_user,
        reason, skip_hammy_check: false,
        send_block_email: reason.start_with?(WARN_VIA_SUPPORT),
        superban: reason.start_with?(SUPERBAN),
      )
    end

    if users.any?
      flash[:notice] = "Blocked users with logins: #{users.map(&:login).join(", ")}"
    end

    render "stafftools/copilot_bulk_blocks/index"
  end
end
