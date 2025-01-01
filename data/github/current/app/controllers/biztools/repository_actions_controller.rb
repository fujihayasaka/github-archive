# typed: true
# frozen_string_literal: true

class Biztools::RepositoryActionsController < BiztoolsController
  before_action :actions_required
  before_action :cast_boolean_params, only: :update
  before_action :cast_float_params, only: :update
  before_action :merge_category_params, only: :update

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:creators]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Iam,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:edit, :index, :creators, :show], optional: true

  def index
    actions = RepositoryAction.discoverable
    actions = actions.order(rank_multiplier: :desc, id: :desc)

    filter_by = filter_params
    actions = actions.where(featured: filter_by[:featured]) if filter_by[:featured].present?
    actions = actions.with_name(filter_by[:name]) if filter_by[:name].present?

    # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
    associated_ids = current_user.associated_repository_ids(min_action: :read)
    # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
    actions = actions.joins(:repository).where("repositories.public = TRUE OR repositories.id IN (?)", associated_ids)

    actions = actions.paginate(per_page: 100, page: current_page)

    if request.xhr?
      render partial: "biztools/repository_actions/actions", locals: { actions: actions, filters: filter_params }
    else
      render "biztools/repository_actions/index", locals: { actions: actions, filters: filter_params }
    end
  end

  def show
    action = RepositoryAction.find(params[:id])
    view = create_view_model(Biztools::RepositoryActions::ShowView, action: action)
    render "biztools/repository_actions/show", locals: { view: view }
  end

  def edit
    action = RepositoryAction.find(params[:id])
    categories = Marketplace::Category.order(:name).not_sponsors_only.to_a

    view = create_view_model(Biztools::RepositoryActions::EditView, action: action, categories: categories)
    render "biztools/repository_actions/edit", locals: { view: view }
  end

  def update
    action = RepositoryAction.find(params[:id])
    inputs = repository_action_params
    action.featured = inputs[:featured] unless inputs[:featured].nil?
    action.rank_multiplier = inputs[:rank_multiplier] if inputs[:rank_multiplier]

    if inputs[:categories] || inputs[:filter_categories]
      categories = []
      if inputs[:categories]
        categories += Marketplace::Category.where(name: inputs[:categories].reject(&:blank?))
      else
        categories += action.regular_categories
      end

      if inputs[:filter_categories]
        categories += Marketplace::Category.where(name: inputs[:filter_categories].reject(&:blank?))
      else
        categories += action.filter_categories
      end

      action.categories = categories
    end

    if action.save
      flash[:notice] = "#{action.name} was updated."
    else
      flash[:error] = action.errors.full_messages.join(", ")
    end

    redirect_to biztools_repository_actions_path(params: { filters: filter_params })
  end

  def destroy
    action = RepositoryAction.find(params[:id])

    if action.action_package_listed
      flash[:error] = "Unable to delete listed action from database"
      return render_404
    end

    # remove linked RepositoryActionRelease records first (if present)
    ids = action.repository_action_releases.pluck(:id)
    RepositoryActionRelease.destroy(ids) if ids.any?

    # remove RepositoryAction record next
    action.destroy

    flash[:notice] = "Okay, #{action.name} has been removed."

    redirect_to biztools_repository_actions_path
  end

  def creators # rubocop:todo GitHub/UseRestfulActions
    creators = if params[:query].present?
      Organization.search(params[:query])
    else
      Configurable::RepositoryActionVerifiedOrg.verified_for_repo_actions.paginate(page: current_page)
    end
    render "biztools/repository_actions/creators", locals: { creators: creators }
  end

  def verify_creator # rubocop:todo GitHub/UseRestfulActions
    creator = Organization.find(params[:creator_id])

    if params[:verify] == "true"
      creator.verify_for_repo_actions(current_user)
      flash[:notice] = "Verified #{creator.login}. Search results should be updated within a few moments"
    else
      creator.unverify_for_repo_actions(current_user)
      flash[:notice] = "Removed verification for #{creator.login}. Search results should be updated within a few moments"
    end

    redirect_to creators_biztools_repository_actions_path(query: params[:query])
  end

  def reindex_creator # rubocop:todo GitHub/UseRestfulActions
    creator = Organization.find(params[:creator_id])
    RepositoryAction.owned_by(creator.login).each(&:synchronize_search_index)
    flash[:notice] = "Repository actions for #{creator.login} are queued to be re-index. Search results should be updated within a few moments"
    redirect_to creators_biztools_repository_actions_path(query: params[:query])
  end

  private

  def repository_action_params
    params.require(:repository_action)
      .permit(:featured, :rank_multiplier, categories: [], filter_categories: [])
  end

  def cast_boolean_params
    %i(featured).each do |attr|
      if (bool_param = params.dig(:repository_action, attr)).present?
        params[:repository_action][attr] = ActiveModel::Type::Boolean.new.cast(bool_param)
      end
    end
  end

  def cast_float_params
    %i(rank_multiplier).each do |attr|
      if (float_param = params.dig(:repository_action, attr)).present?
        params[:repository_action][attr] = ActiveModel::Type::Float.new.cast(float_param)
      end
    end
  end

  def merge_category_params
    categories = []

    if (first_category = params[:repository_action].delete(:primaryCategoryName)).present?
      categories << first_category
    end

    if (second_category = params[:repository_action].delete(:secondaryCategoryName)).present?
      categories << second_category
    end

    if categories.present?
      params[:repository_action][:categories] = categories
    end
  end

  def filter_params # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @filter_params ||= [:name, :featured].each_with_object({}) do |key, filters|
      filters[key] = params.dig(:filters, key).presence
    end
  end

  def actions_required
    render_404 unless GitHub.actions_enabled?
  end
end
