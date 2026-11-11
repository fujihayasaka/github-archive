# typed: true
# frozen_string_literal: true

class UserListChecksController < ApplicationController
  include UserListsControllerMethods

  PERMITTED_CHECK_ATTRIBUTES = Set.new(%w(name description)).freeze

  before_action :login_required
  before_action :require_same_user
  before_action :require_permitted_attribute

  def create
    list = existing_list || this_user.lists.new
    list.assign_attributes(check_attribute => params[:value])
    return head(:ok) if list.valid?
    return head(:ok) unless list.errors.include?(check_attribute)

    message = list.errors.full_messages_for(check_attribute).join(". ") + "."
    render plain: message, status: :unprocessable_entity
  end

  private

  def target_for_conditional_access
    # this_user is guaranteed to be non-nil by require_this_user filter.
    this_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def require_permitted_attribute
    head :forbidden unless check_attribute
  end

  def check_attribute # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @check_attribute if defined?(@check_attribute)
    @check_attribute = if PERMITTED_CHECK_ATTRIBUTES.include?(params[:attr])
      params[:attr]
    end
  end

  def existing_list # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @user_list if defined?(@user_list)
    @user_list = if params[:list_id]
      this_user.lists.find(params[:list_id])
    end
  end
end
