# typed: true
# frozen_string_literal: true

class CopilotBusinessSignupEnterpriseListController < CopilotBusinessSignupController
  depends_on_clusters ApplicationRecord::Mysql1,
                    ApplicationRecord::Collab,
                    ApplicationRecord::Mysql2,
                    ApplicationRecord::IamAbilities,
                    ApplicationRecord::NotificationsEntries

  def index
    businesses = user_owned_businesses
    if params[:with] == "copilot-business" && copilot_business_trial_signup_blocked?
      businesses = businesses.not_trial
    end

    render Signup::SelectAccountListComponent.new(
      accounts: businesses
        .for_query(params[:query])
        .paginate(page: current_page, per_page: PAGE_SIZE),
      account_type: Signup::SelectAccountListComponent::AccountType::Business,
      benefit: params[:with]
    ), formats: [:html, :html_fragment], layout: false
  end
end
