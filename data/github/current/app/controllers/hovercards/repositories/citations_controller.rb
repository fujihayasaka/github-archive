# typed: strict
# frozen_string_literal: true

class Hovercards::Repositories::CitationsController < ApplicationController
  include RepositoryControllerMethods

  before_action :ask_the_gatekeeper
  before_action :require_xhr
  before_action :login_required, only: [:file_template]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:file_template]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:sidebar_partial]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :sidebar_partial], optional: true

  sig { void }
  def show
    citation = Repositories::Citation.from_repository(current_repository, tree_name: params[:tree_name])

    return render_404 unless citation

    GitHub.dogstats.increment("citation.repo.show")
    render "hovercards/repositories/citations/show", locals: { citation: citation }, layout: false
  end

  sig { void }
  def sidebar_partial # rubocop:todo GitHub/UseRestfulActions
    return head :no_content unless Repositories::Citation.exists?(current_repository, tree_name: params[:tree_name])

    render partial: "hovercards/repositories/citations/sidebar_partial",
           layout: false,
           locals: {
             current_repository: current_repository,
             tree_name: params[:tree_name]
           }
  end

  sig { void }
  def file_template # rubocop:todo GitHub/UseRestfulActions
    GitHub.dogstats.increment("citation.file_template")
    render "hovercards/repositories/citations/file_template",
            layout: false,
            locals: {
              title: current_repository.name,
              name_with_display_owner: current_repository.name_with_display_owner
            }
  end
end
