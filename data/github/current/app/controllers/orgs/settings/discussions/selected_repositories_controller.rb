# typed: true
# frozen_string_literal: true

# Provides repositories to set as target repository for org-level discussions
class Orgs::Settings::Discussions::SelectedRepositoriesController < Orgs::Controller
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Iam,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  DEFAULT_MAX_RESULTS = 100

  before_action :login_required
  before_action :organization_admin_required
  before_action :ensure_discussions_available

  def index
    render partial: "settings/organization/discussions/selected_repositories/index", locals: {
      selected_repository: selected_repository,
      repositories: repositories,
    }, formats: :html
  end

  private

  memoize def selected_repository
    current_organization.discussion_repository&.repository
  end

  def repositories
    if params[:q].blank?
      results = current_organization.repositories.limit(DEFAULT_MAX_RESULTS)
      # Ensure that the currently selected repository is included by default
      return results unless selected_repository.present? && !results.include?(selected_repository)
      [selected_repository] + results
    else
      results = Search::Queries::RepoQuery.new(
        current_user: current_user,
        user_session: user_session,
        remote_ip: remote_ip,
        cap_filter: cap_filter,
        phrase: "org:#{current_organization.login} in:name \"#{params[:q]}\"", # rubocop:todo GitHub/DoNotAllowLogin https://github.com/github/proxima/issues/1194
        include_forks: true,
        per_page: Repository.per_page,
      ).execute.results
      results.map { |result| result["_model"] }
    end
  end

  def ensure_discussions_available
    render_404 unless GitHub.discussions_available_on_platform?
  end
end
