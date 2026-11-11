# typed: true
# frozen_string_literal: true

class Businesses::ProfilesFooterController < Businesses::BusinessController
  before_action :business_owner_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:show]

  def show
    fill_footers
    render "businesses/settings/profile_footer"
  end

  def update
    if this_business.update(footer_params)
      redirect_to settings_profile_footer_enterprise_path(this_business), notice: "Custom footer has been updated."
    else
      flash.now[:error] = this_business.errors.full_messages.join(", ")
      fill_footers
      render "businesses/settings/profile_footer"
    end
  end

  private

  def fill_footers
    (GitHub.max_business_footer_count - this_business.footer_links.size).times { this_business.footer_links.build }
  end

  def footer_params
    params.require(:business).permit(footer_links_attributes: %i[id title url _destroy]).compact_blank
  end
end
