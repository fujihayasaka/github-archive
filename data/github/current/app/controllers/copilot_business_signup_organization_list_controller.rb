# typed: true
# frozen_string_literal: true

class CopilotBusinessSignupOrganizationListController < CopilotBusinessSignupController

  depends_on_clusters ApplicationRecord::Mysql1,
                    ApplicationRecord::Collab,
                    ApplicationRecord::Mysql2,
                    ApplicationRecord::IamAbilities,
                    ApplicationRecord::NotificationsEntries

  def index
    orgs = user_owned_orgs.includes(:profile).paginate(page: current_page, per_page: PAGE_SIZE)
    query = params[:query].to_s.strip.downcase  # query will get sanitized in the like_login_or_profile_name scope
    orgs = orgs.like_login_or_profile_name(query) if query.present?

    render partial: "signup/select_orgs_list", formats: [:html, :html_fragment], layout: false, locals: {
     organizations: orgs,
    }
  end
end
