# typed: true
# frozen_string_literal: true

class EditRepositories::PullRequestCreationCapBypassController < AbstractRepositoryController
  before_action :login_required
  before_action :ensure_admin_access
  before_action :writable_repository_required
  before_action :ensure_feature_enabled

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "EditRepositories::PullRequestCreationCapBypassController#add_users",
    "EditRepositories::PullRequestCreationCapBypassController#remove_users",
  ]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    only: [:user_suggestions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    only: [:add_users, :remove_users]

  # GET settings/pull_request_creation_cap_bypass/user_suggestions
  def user_suggestions # rubocop:disable GitHub/UseRestfulActions
    users = if params[:q].present?
      AutocompleteQuery.new(
        current_user,
        params[:q].to_s,
        include_teams: false,
      ).suggestions.select(&:user?)
    else
      # Priority 1: recent contributors who don't already have write access.
      # These are the most likely candidates to be granted a bypass since they
      # are actively contributing but lack the permissions to open PRs freely.
      contributor_ids = CommitContributions.domain.contributed_user_ids_by_recency(
        repository: current_repository,
        limit: 20,
      )
      write_access_ids = current_repository.direct_member_ids(min_action: :write)
      non_writer_contributor_ids = contributor_ids.reject { |id| write_access_ids.include?(id) }.first(10)
      contributors = User.where(id: non_writer_contributor_ids).select(&:user?)

      # Priority 2: if there are fewer than 10 contributors without write access,
      # fill remaining slots with org members who also lack write access.
      remaining = 10 - contributors.size
      if remaining > 0 && current_repository.in_organization?
        exclude_ids = write_access_ids | non_writer_contributor_ids.to_set
        # Use a small fixed cap rather than exclude_ids.size to avoid expensive
        # large-limit queries on orgs with many write-access members.
        filler = current_repository.organization
          .visible_users_for(current_user, actor_ids: nil, limit: [remaining * 5, 50].min)
          .reject { |u| exclude_ids.include?(u.id) }
          .first(remaining)
        contributors + filler
      else
        contributors
      end
    end

    visible_users = cap_filter.authorized_resources(users)
    existing_bypass_ids = PullRequestCreationConfig.new(current_repository).pull_request_creation_cap_bypass_user_ids.to_set
    visible_users = visible_users.reject { |u| existing_bypass_ids.include?(u.id) || u.id == current_user.id }

    respond_to do |format|
      format.html_fragment do
        render partial: "edit_repositories/interaction_limits/pull_request_creation_cap_bypass_user_suggestions",
               formats: :html,
               locals: { users: visible_users, repo: current_repository }
      end
      format.html do
        render partial: "edit_repositories/interaction_limits/pull_request_creation_cap_bypass_user_suggestions",
               formats: :html,
               locals: { users: visible_users, repo: current_repository }
      end
    end
  end

  # POST settings/pull_request_creation_cap_bypass/users
  def add_users # rubocop:disable GitHub/UseRestfulActions
    logins = Array(params[:logins]).select(&:present?)
    config = PullRequestCreationConfig.new(current_repository)
    users = User.where(login: logins).to_a
    return render_404 if users.empty? || users.size != logins.size

    begin
      config.add_pull_request_creation_cap_bypass_users(users: users)
    rescue ArgumentError => e
      respond_to do |format|
        format.turbo_stream { render "edit_repositories/interaction_limits/pull_request_creation_cap_update", locals: { repository: current_repository }, status: :unprocessable_entity }
        format.html do
          if request.xhr?
            head :unprocessable_entity
          else
            flash[:error] = e.message
            redirect_to :back
          end
        end
        format.all { head :unprocessable_entity }
      end
      return
    end

    respond_to do |format|
      format.turbo_stream { render "edit_repositories/interaction_limits/pull_request_creation_cap_update", locals: { repository: current_repository } }
      format.html do
        if request.xhr?
          head :ok
        else
          redirect_to :back
        end
      end
      format.all { head :ok }
    end
  end

  # DELETE settings/pull_request_creation_cap_bypass/users
  def remove_users # rubocop:disable GitHub/UseRestfulActions
    user_ids = Array(params[:user_ids]).map(&:to_i).select(&:positive?)
    config = PullRequestCreationConfig.new(current_repository)
    users = User.where(id: user_ids).to_a
    config.remove_pull_request_creation_cap_bypass_users(users: users)

    respond_to do |format|
      format.turbo_stream { render "edit_repositories/interaction_limits/pull_request_creation_cap_update", locals: { repository: current_repository } }
      format.html do
        if request.xhr?
          head :ok
        else
          redirect_to :back
        end
      end
      format.all { head :ok }
    end
  end

  private

  def ensure_feature_enabled
    render_404 unless FeatureFlag.vexi.enabled?(:pull_request_creation_cap_allowlist, current_repository, default: false)
  end
end
