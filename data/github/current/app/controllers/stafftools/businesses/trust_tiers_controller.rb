# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::TrustTiersController < Stafftools::Businesses::BusinessBaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show]

  def show
    render "stafftools/businesses/trust_tiers/show"
  end

  def change_tier # rubocop:todo GitHub/UseRestfulActions
    new_tier = params[:new_tier].to_i

    new_tier_name = TrustTiers::Tier.tier_name(new_tier)
    TrustTiers::BusinessOverride.set(this_business, new_tier)

    Copilot::BpoTrustTierCache.invalidate(this_business)
    Copilot::BpoTrustTierCache.emit_gcu_cache_bust(this_business)

    notice = new_tier == -1 ? "Tier reset to calculated" : "Tier changed to #{new_tier_name}"
    notice += ". This could take up to an hour to take effect in Codespaces."

    payload = {
      business: this_business,
      note: notice,
      new_tier_name: new_tier_name
    }.merge(GitHub.guarded_audit_log_staff_actor_entry(current_user))

    instrument("staff.change_trust_tier", payload)

    flash[:notice] = notice
    redirect_to action: "show"
  end
end
