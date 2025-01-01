# typed: true
# frozen_string_literal: true

class CloneTemplateRepositoriesController < AbstractRepositoryController
  before_action :login_required

  javascript_bundle :repositories

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:new]

  include RepositoriesHelper

  def new
    # For users that still have the `/generate` route bookmarked
    redirect_to clone_template_repository_url(current_user, current_repository)
  end
end
