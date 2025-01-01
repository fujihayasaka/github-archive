# typed: true
# frozen_string_literal: true

class Businesses::UserNamespaceRepositoriesController < Businesses::BusinessController
  before_action :valid_business
  before_action :login_required
  before_action :business_owner_required, except: [:update]
  before_action only: [:update] do
    T.bind(self, Businesses::BusinessController)
    business_access_required(allow_members: true)
  end

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:index]

  ERROR_UNLOCK_REPOSITORY = "Could not gain access to the repository"

  REPO_STATUS = {
    "deleted" => :deleted,
    "accessible" => :unlocked,
    nil => :active,
  }.freeze

  def index
    return render_404 unless this_business.show_user_namespace_repositories?

    query_args = parse_query_string(query_param, filter_map: BusinessesHelper::USER_NAMESPACE_REPOSITORY_FILTER)
    status = REPO_STATUS[query_args[:status]]
    sort_order = parse_sort_order(query_args)

    show_unlock = this_business.can_user_unlock_user_namespace_repos?(current_user)
    unlocked_repository_ids = if show_unlock
      # Determine if a link should be shown. This is not granting any abilities.
      RepositoryUnlock.active_for_user(current_user).pluck(:repository_id)
    else
      []
    end

    user_namespace_repositories = this_business.user_namespace_repositories(
      query: query_args[:query],
      status: status,
      repository_ids: status == :unlocked ? unlocked_repository_ids : [],
      sort_direction: sort_order[:sort_direction],
      sort_field: sort_order[:sort_field],
      )
    return render_404 if user_namespace_repositories.nil?

    repositories = user_namespace_repositories
      .paginate(page: current_page, per_page: PAGE_SIZE)

    respond_to do |format|
      format.html do
        if request.xhr?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "businesses/repositories/user_namespace_repositories_list", locals: {
            query: query_param,
            repositories: repositories,
            show_unlock: show_unlock,
            unlocked_repository_ids: unlocked_repository_ids,
          }
        else
          render "businesses/repositories/user_namespace_repositories", locals: {
            query: query_param,
            repositories: repositories,
            show_unlock: show_unlock,
            unlocked_repository_ids: unlocked_repository_ids,
            status: query_args[:status],
            sort_direction: sort_order[:sort_direction],
            sort_field: sort_order[:sort_field],
          }
        end
      end
    end
  end

  def update
    operation = params[:operation]&.to_sym

    return render_404 if
      params[:repository_id].nil? ||
      operation.nil? ||
      !this_business.can_user_unlock_user_namespace_repos?(current_user)

    repo = Repository.find_by(id: params[:repository_id])
    if repo.nil?
      flash[:error] = ERROR_UNLOCK_REPOSITORY
      redirect_to :back
      return
    end

    case operation
    when :unlock
      return unlock(repo)
    end

    if request.xhr?
      render status: 422, plain: ERROR_UNLOCK_REPOSITORY
    else
      flash[:error] = ERROR_UNLOCK_REPOSITORY
      redirect_to :back
    end
  end

  private

  def unlock(repo)
    # A reason is required if we're on enterprise
    reason = "Enterprise user enabled temporary access to user-owned repo" if GitHub.enterprise?

    # returns the unlock or false
    repo_unlock = current_user.unlock_repository(repo, reason)
    if repo_unlock
      flash[:notice] = "Temporary access granted to #{T.must(repo).name_with_display_owner}. This access will expire in #{RepositoryUnlock::DEFAULT_EXPIRY.inspect}."
    else
      flash[:error] = ERROR_UNLOCK_REPOSITORY
    end

    return_url = url_from(params[:return_to]) || :back
    redirect_to return_url
  end

  def valid_business
    return if GitHub.enterprise?
    emu_business_required
  end
end
