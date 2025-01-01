# typed: true
# frozen_string_literal: true

class Stafftools::TrustTiersController < StafftoolsController
  layout "layouts/stafftools/user/content"

  before_action :dotcom_required
  before_action :ensure_user_exists

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    render "stafftools/trust_tiers/index"
  end

  def change_tier # rubocop:todo GitHub/UseRestfulActions
    new_tier = params[:new_tier] # keep as a string

    new_tier_name = TrustTiers::Tier.tier_name(new_tier.to_i)
    # set setting value
    this_user.settings.set!(:trust_tier, new_tier)

    # setup flash notice
    notice = "Tier changed to #{new_tier_name}"
    if new_tier == "-1"
      notice = "Tier reset to calculated"
    end

    notice += ". This could take up to an hour to take effect in Codespaces."

    payload = {
      user: this_user,
      note: notice,
      new_tier_name: new_tier_name
    }.merge(GitHub.guarded_audit_log_staff_actor_entry(current_user))

    # instrument this
    instrument("staff.change_trust_tier", payload)

    flash[:notice] = notice
    redirect_to action: "index"
  end

end
