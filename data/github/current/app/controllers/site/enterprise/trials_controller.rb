# typed: true
# frozen_string_literal: true

class Site::Enterprise::TrialsController < Site::Enterprise::BaseController
  depends_on_clusters ApplicationRecord::Mysql1, only: [:start]

  depends_on_clusters ApplicationRecord::Collab, only: [:start]

  def start # rubocop:todo GitHub/UseRestfulActions
    if logged_in?
      redirect_to new_organization_path(plan: GitHub::Plan.business_plus, trial_acquisition_channel: "resources")
    else
      redirect_to signup_path(plan: GitHub::Plan.business_plus, setup_organization: true, trial_acquisition_channel: "resources")
    end
  end
end
