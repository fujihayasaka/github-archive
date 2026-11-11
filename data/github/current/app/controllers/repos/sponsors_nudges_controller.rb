# typed: true
# frozen_string_literal: true

class Repos::SponsorsNudgesController < AbstractRepositoryController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::IamAbilities,
    only: [:show]

  def show
    render Sponsors::Repositories::IssueNudgeComponent.new(repository: current_repository), layout: false
  end
end
