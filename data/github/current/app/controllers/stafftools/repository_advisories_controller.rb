# typed: true
# frozen_string_literal: true

class Stafftools::RepositoryAdvisoriesController < StafftoolsController

  before_action :ensure_repo_exists

  layout "layouts/stafftools/repository/collaboration"

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: %i[index show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show],
    optional: true

  def index
    @advisories = current_repository.repository_advisories.order("id DESC").paginate \
      page: params[:page] || 1,
      per_page: 25
    render "stafftools/repository_advisories/index"
  end

  def show
    query = "data.repository_advisory_id:#{this_repository_advisory.id} OR (data.user_content_id:#{this_repository_advisory.id} AND data.user_content_type:#{this_repository_advisory.class} AND action:user_content_edit.*)"
    if GitHub.driftwood_ade_queries_enabled?
      query = " webevents | where repository_advisory_id == #{this_repository_advisory.id} or (action startswith 'user_content_edit' and user_content_id == #{this_repository_advisory.id} and user_content_type == '#{this_repository_advisory.class}')"
    end
    fetch_audit_log_teaser(query)
    render "stafftools/repository_advisories/show"
  end

  def database # rubocop:todo GitHub/UseRestfulActions
    respond_to do |f|
      f.html do
        render "stafftools/repository_advisories/database"
      end
    end
  end

  def destroy
    advisory_id = this_repository_advisory.ghsa_id

    this_repository_advisory.destroy

    instrument \
      "staff.delete_repository_advisory",
      user: current_repository.owner,
      repo: current_repository,
      note: "Deleted advisory #{current_repository.nwo} #{advisory_id}"

    flash[:notice] = "Advisory #{advisory_id} deleted"
    redirect_to gh_stafftools_repository_advisories_path(current_repository)
  end
end
