# typed: true
# frozen_string_literal: true

class CopilotBusinessSignupOrganizationListController < CopilotBusinessSignupController
  depends_on_clusters ApplicationRecord::Mysql1,
                    ApplicationRecord::Collab,
                    ApplicationRecord::Mysql2,
                    ApplicationRecord::IamAbilities,
                    ApplicationRecord::NotificationsEntries

  def index
    orgs = user_owned_orgs.includes(:profile)
    query = params[:query].to_s.strip.downcase  # query will get sanitized in the like_login_or_profile_name scope
    orgs = orgs.like_login_or_profile_name(query) if query.present?

    if params[:with] == "risk-assessment"
      filtered = orgs.select { |org| ::SecurityProducts::AccessControl::RiskAssessments.new(org).has_access_to_risk_assessments?(current_user) }
      orgs = filtered.paginate(page: current_page, per_page: PAGE_SIZE)
    else
      orgs = orgs.paginate(page: current_page, per_page: PAGE_SIZE)
    end

    render Signup::SelectAccountListComponent.new(
      accounts: orgs,
      account_type: Signup::SelectAccountListComponent::AccountType::Org,
      benefit: params[:with]
    ), formats: [:html, :html_fragment], layout: false
  end
end
