# typed: true
# frozen_string_literal: true

class CopilotBusinessSignupEnterpriseListController < CopilotBusinessSignupController

  depends_on_clusters ApplicationRecord::Mysql1,
                    ApplicationRecord::Collab,
                    ApplicationRecord::Mysql2,
                    ApplicationRecord::IamAbilities,
                    ApplicationRecord::NotificationsEntries

  def index
    render partial: "signup/select_business_list", formats: [:html, :html_fragment], layout: false, locals: {
     businesses: user_owned_businesses
      .for_query(params[:query])
      .paginate(page: current_page, per_page: PAGE_SIZE),
    }
  end

end
