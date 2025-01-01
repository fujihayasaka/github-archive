# typed: true
# frozen_string_literal: true

class Discussions::CategoriesController < Discussions::BaseController
  include DiscussionsControllerMethods

  before_action :login_required, only: %i(create new edit update destroy)
  before_action :set_org_context_crumb, if: :is_org_level?

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    only: [:index, :new, :edit]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :new, :edit], optional: true

  preload_features [
    :permission_enforcer_with_caching,
    :emu_sso_login,
    :two_factor_checkup,
    :notifyd_label_subscriptions,
    :skip_open_graph_url_encoding,
    :stacks_toggle,
    :insights_api_local_development,
    :notifications_async_watch_repo_button,
    :html_pipeline_bad_emoji,
    :emu_vss_business,
    :allow_internal_org_config_repo_if_public_repos_disabled, # Global health repo for EMU orgs
    :enterprise_banners_repo_level,
    :global_health_files_repository_loader_new_fetch_implementation, # Global health repo for EMU orgs
    :authenticated_avatars,
    :api_insights_rest,
    :copilot_conversational_ux_license_check,
    :copilot_for_partners,
    :owner_scoped_github_apps,
    :stafftools_tenant_use_parameter,
    :proxima_repository_advisories,
    :copilot_natural_language_github_search,
    :skip_anon_jump_to_suggestions_enabled,
  ], only: [:new, :edit]

  def index
    current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
    if current_repository.organization_discussion.present? && !is_org_level?
      return redirect_to org_discussions_categories_path(current_repository.owner)
    end

    return render_404 unless current_user&.can_create_discussion_category?(current_repository)

    render "discussion_categories/index",
      locals: {
        discussion_categories: current_repository.available_discussion_categories,
        discussion_sections: current_repository.discussion_sections
      }
  end

  def new
    return render_404 unless current_user.can_create_discussion_category?(current_repository)
    current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
    if current_repository.organization_discussion.present? && !is_org_level?
      return redirect_to new_org_discussions_category_path(current_repository.owner)
    end
    render "discussion_categories/new", locals: { category: DiscussionCategory.new(repository: current_repository) }
  end

  def create
    return render_404 unless current_user.can_create_discussion_category?(current_repository)
    current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }

    # only maintainer+ users can create announcement categories
    if supports_announcements? && !current_repository.can_create_discussion_announcements?(current_user)
      flash[:error] = "Only admins and maintainers can create categories in the announcement format."
      return redirect_to agnostic_categories_path(repository: current_repository, org_param: org_param)
    end

    created_category = current_repository.discussion_categories.build(category_params_with_supports)
    created_category.actor = current_user
    if created_category.save
      flash[:notice] = "Category \"#{created_category.name}\" has been created."
      redirect_to agnostic_categories_path(repository: current_repository, org_param: org_param)
    else
      render "discussion_categories/new", locals: { category: created_category }
    end
  end

  def edit
    return render_404 unless category.modifiable_by?(current_user)
    current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
    if current_repository.organization_discussion.present? && !is_org_level?
      return redirect_to edit_org_discussions_category_path(current_repository.owner)
    end
    render "discussion_categories/edit", locals: { category: category }
  end

  def update
    return render_404 unless category.modifiable_by?(current_user)

    # don't allow existing poll category format to change to other format and vice versa
    if category.supports_polls? != supports_polls?
      return render_404
    end

    current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }

    # only maintainer+ users can update categories to announcement format
    if supports_announcements? && !current_repository.can_create_discussion_announcements?(current_user)
      flash[:error] = "Only admins and maintainers can update categories to the announcement format."
      return redirect_to agnostic_categories_path(repository: current_repository, org_param: org_param)
    end

    category.actor = current_user
    if category.update(category_params_with_supports)
      flash[:notice] = "Category \"#{category.name}\" has been updated."
      redirect_to agnostic_categories_path(repository: current_repository, org_param: org_param)
    else
      render "discussion_categories/edit", locals: { category: category }
    end
  end

  def emoji_picker # rubocop:todo GitHub/UseRestfulActions
    render "discussion_categories/emoji_picker", layout: false, locals: {
      emoji_name: params[:emoji_name],
    }
  end

  def destroy
    return render_404 unless category.deletable_by?(current_user)
    category.mark_as_deleting!

    current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }

    if !DiscussionCategory.any_not_deleting?(category.repository.available_discussion_categories.where.not(id: category.id))
      flash[:error] = "The last category \"#{category}\" cannot be deleted."
    else
      category.actor = current_user
      new_category = current_repository.available_discussion_categories.find(params[:new_category_id])

      if !category.supports_polls? && new_category.supports_polls?
        return render_404
      end

      if params[:new_category_id].to_i != category.id && new_category.present?
        reassign_discussions(new_category)

        if category.destroy
          category.freeze
          flash[:notice] = "Category \"#{category}\" has been deleted."
        else
          flash[:error] = general_delete_error
        end
      end
    end

    redirect_to agnostic_categories_path(repository: current_repository, org_param: org_param)
  ensure
    category.unmark_as_deleting! unless category.frozen?
  end

  private

  memoize def category
    current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
    current_repository.available_discussion_categories.find(params[:id])
  end

  def category_params
    params.require(:category).permit(:name, :description, :emoji, :discussion_section_id)
  end

  def category_params_with_discussion_section_id
    @category_params_with_discussion_section_id = category_params
    @category_params_with_discussion_section_id[:discussion_section_id] = nil if category_params[:discussion_section_id] == "0"
    @category_params_with_discussion_section_id
  end

  def category_params_with_supports
    @category_params_with_supports = category_params_with_discussion_section_id
    @category_params_with_supports[:supports_mark_as_answer] = supports_mark_as_answer?
    @category_params_with_supports[:supports_announcements] = supports_announcements?
    @category_params_with_supports[:supports_polls] = supports_polls?
    @category_params_with_supports
  end

  def set_error_flash(category, verb)
    if !category.errors.empty?
      flash[:error] = category.errors.full_messages.join(", ")
    else
      flash[:error] = "Could not #{verb} category \"#{category.name}\" at this time."
    end
  end

  def reassign_discussions(new_category)
    current_repository = self.current_repository
    return unless current_repository

    discussions_scope = current_repository
      .discussions
      .where(category_id: category.id)
    discussion_ids = discussions_scope.pluck(:id)

    if category.supports_polls? && !new_category.supports_polls?
      discussions_scope.each { |discussion| discussion.poll&.destroy }
    end

    discussions_scope.update_all(category_id: new_category.id)

    # Since `#update_all` makes a SQL query to set the new `category_id`, it skips
    # the `after_commit` callback that reindexes these discussions. So we have
    # to call this manually.
    discussion_ids.each do |discussion_id|
      Search.add_to_search_index("discussion", discussion_id)
    end
  end

  def general_delete_error
    "Could not delete category \"#{category}\" at this time."
  end

  def supports_mark_as_answer?
    params[:supports] == "mark_as_answer"
  end

  def supports_announcements?
    params[:supports] == "announcements"
  end

  def supports_polls?
    params[:supports] == "polls"
  end
end
