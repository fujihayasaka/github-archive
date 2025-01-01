# typed: true
# frozen_string_literal: true

class UserListsController < ApplicationController
  include ProfilesHelper # for `ensure_profile_visible`
  include UserListsControllerMethods
  include EnterpriseManagedUsersHelper

  before_action :require_user_list, only: [:show, :update, :destroy]
  before_action :require_xhr, only: [:create]
  before_action :require_same_user, only: [:create, :update, :destroy]
  before_action :require_valid_repository_if_present, only: [:create]
  before_action :ensure_profile_visible

  stylesheet_bundle :profile

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    if pjax?
      render UserLists::ItemsComponent.new(list: user_list, page: current_page), layout: false
    else
      layout_data = Profiles::User::LayoutData.preload(
        profile_user: this_user,
        viewer: current_user,
        active_tab: nil,
      )

      render "user_lists/show", locals: {
        layout_data: layout_data,
        list: user_list,
      }
    end
  end

  def create
    list = current_user.lists.build(user_list_params)
    if list.save
      did_star = false

      if repository
        # We don't really have a good way to report if any of this fails. You'll notice pretty quickly when the user
        # list menu updates without the new repository.
        already_starred = repository.starred_by?(current_user)
        unless already_starred
          did_star = current_user.star(repository, context: "user_list")
        end

        if already_starred || did_star
          list.items.create(repository: repository)
        end
      end
      render "user_lists/url", locals: {
        url: user_list_path(current_user, list.slug),
        did_star: did_star,
        star_count: repository&.stargazer_count || 0,
      }
    else
      render(UserLists::CreateDialogFormComponent.new(user_list: list), layout: false, status: :unprocessable_entity)
    end
  end

  def update
    old_list = user_list.dup.tap { |ul| ul.id = user_list.id }
    if user_list.update(user_list_params)
      user_list.instrument_hydro_update(old_list: old_list)
      render "user_lists/url", layout: false, locals: {
        url: user_list_path(current_user, user_list.slug),
        did_star: false,
        star_count: 0,
      }
    else
      render(UserLists::EditDialogFormComponent.new(user_list: user_list), layout: false, status: :unprocessable_entity)
    end
  end

  def destroy
    if user_list.destroy
      flash[:notice] = "Deleted \"#{user_list}\"."
    else
      flash[:error] = "Could not delete your list at this time."
    end

    redirect_to user_path(current_user, params: { tab: "stars" })
  end

  private

  def target_for_conditional_access
    # this_user is guaranteed to be non-nil by require_this_user filter.
    # Falling back to :no_target_for_conditional_access is an anti-pattern, but:
    # - using prepend_before_action to require this_user before conditional access is checked is also a security hole
    #   and disallowed by Sentinel
    # - raising an exception here also causes the conditional access tests to fail
    this_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def require_user_list
    render_404 unless user_list
  end

  def render_error(message, status)
    user_list = UserList.new
    user_list.errors.add(:base, message)
    render(
      UserLists::CreateDialogFormComponent.new(user_list:),
      layout: false,
      status:
    )
  end

  def require_valid_repository_if_present
    return unless params.has_key?(:repository_id)

    return render_error(
      "Repository not found",
      :unprocessable_entity
    ) if repository.nil?

    return render_error(
      "Your lists cannot include repositories outside your enterprise #{enterprise_name}",
      :unauthorized
    ) if emu_contribution_blocked?(repository)
  end

  def user_list # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @user_list if defined?(@user_list)
    @user_list = if this_user
      this_user.lists.find_by(slug: params[:slug])
    end
  end

  def user_list_params
    params.require(:user_list).permit(:name, :description)
  end
end
