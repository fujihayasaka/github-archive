# typed: true
# frozen_string_literal: true

class UserListMenuBatchesController < ApplicationController
  include UserListsControllerMethods

  before_action :login_required
  before_action :require_same_user

  def create
    lists_applied_set = UserList.applied_to(
      user_id: current_user.id,
      repository_ids: repositories.map(&:id),
    )

    menus_by_repo = repositories.each_with_object({}) do |repository, hash|
      hash[repository.id] = render_to_string(UserLists::MenuContentComponent.new(
        repository: repository,
        lists_applied_set: lists_applied_set,
      ), layout: false)
    end
    render json: menus_by_repo
  end

  private def target_for_conditional_access
    # this_user is guaranteed to be non-nil by require_this_user filter.
    return :no_target_for_conditional_access unless this_user # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    this_user
  end

  private

  def repositories # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @repositories ||= begin
      ids = params.fetch(:repository_ids, []).uniq
      promises = Repository.where(id: ids).map do |repo|
        repo.async_readable_by?(current_user).then do |is_readable|
          is_readable ? repo : nil
        end
      end
      visible_repositories = Promise.all(promises).sync.compact
      cap_filter.authorized_resources(visible_repositories)
    end
  end
end
