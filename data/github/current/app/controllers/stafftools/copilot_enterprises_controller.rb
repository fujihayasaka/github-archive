# typed: true
# frozen_string_literal: true

class Stafftools::CopilotEnterprisesController < StafftoolsController

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
    # for this, we are going to load up the page of businesses that are Copilot ONLY - i.e. they have no SDLC
    # functionality and can only manage Copilot seats
    #
    # until the MEAO team is able to roll out the business level restrictions to remove the SDLC functionality
    # for these customers, we are going to allow them to have full GHEC on the honor system.
    # well, really "trust but verify"
    #
    render "stafftools/copilot_enterprises/index", locals: {
      businesses: Copilot::CopilotEnterprise.sdlc_details(page: current_page)
    }
  end
end
