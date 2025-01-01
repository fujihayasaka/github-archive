# typed: true
# frozen_string_literal: true

class Stafftools::Users::IpAllowlistsController < StafftoolsController
  before_action :ensure_user_exists
  before_action :ensure_org_not_user
  before_action :ensure_ip_allowlists_available

  layout "layouts/stafftools/organization/security"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    entries = IpAllowlistEntry.
      usable_for(this_user).
      for_query(params[:query]).
      order(allow_list_value: :asc).
      paginate(page: params[:page])
    installed_app_entries = IpAllowlistEntry.
      installed_for(this_user).
      for_query(params[:query]).
      order(allow_list_value: :asc).
      paginate(page: params[:page])

    render(
      "stafftools/users/ip_allowlists/show",
      locals: {
        organization: this_user,
        ip_allowlist_entries: entries,
        installed_app_ip_allowlist_entries: installed_app_entries,
      },
    )
  end

  def destroy
    if params[:reason].blank?
      flash[:error] = "You must provide a reason for disabling the IP allow list."
    elsif this_user.ip_allowlist_enabled_policy?
      # Don't let staff disable an IP allow list on an org if the IP allow list
      # is configured on the owning enterprise account (and inherited by the org).
      flash[:error] = "You must disable the IP allow list on the owning enterprise account."
    else
      this_user.disable_ip_allowlist(actor: current_user, reason: params[:reason])
      flash[:notice] = "Disabled IP allow list."
    end

    redirect_to stafftools_user_ip_allowlist_path(this_user)
  end
end
