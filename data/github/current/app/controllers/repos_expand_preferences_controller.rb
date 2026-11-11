# typed: true
# frozen_string_literal: true

class ReposExpandPreferencesController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required

  allow_verified_fetch only: [:update]

  def update
    success_message = params

    new_expanded_tree = params[:tree_view_expanded_preference]
    if new_expanded_tree.present?
      current_user.settings.set!(:tree_view_expanded, new_expanded_tree)
      success_message = "Expand/collapse preference successfully saved."
    end

    new_copilot_expanded_tree = params[:copilot_tree_view_expanded_preference]
    if new_copilot_expanded_tree.present?
      current_user.settings.set!(:copilot_tree_view_expanded, new_copilot_expanded_tree)
      success_message = "Copilot expand/collapse preference successfully saved."
    end

    new_copilot_show_diff = params[:copilot_show_diff_preference]
    if new_copilot_show_diff.present?
      current_user.settings.set!(:copilot_show_diff, new_copilot_show_diff)
      success_message = "Copilot show diff preference successfully saved."
    end

    new_expanded_symbols = params[:symbols_view_expanded_preference]
    if new_expanded_symbols.present?
      current_user.settings.set!(:symbols_view_expanded, new_expanded_symbols)
      success_message = "Expand/collapse preference successfully saved."
    end

    new_wrap_lines = params[:code_line_wrap_enabled]
    if new_wrap_lines.present?
      current_user.settings.set!(:code_line_wrap_enabled, new_wrap_lines)
      success_message = "Wrap lines preference successfully saved."
    end

    orgs_repos_compact_mode = params[:orgs_repos_compact_mode]
    if orgs_repos_compact_mode.present?
      current_user.settings.set!(:orgs_repos_compact_mode, orgs_repos_compact_mode)
      success_message = "Org repos compact mode preference successfully saved."
    end

    repos_finder_compact_mode = params[:repos_finder_compact_mode]
    if repos_finder_compact_mode.present?
      current_user.settings.set!(:repos_finder_compact_mode, repos_finder_compact_mode)
      success_message = "Repos finder compact mode preference successfully saved."
    end

    render json: { notice: success_message }
  end


  private

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    # This controller requires the user to be logged in, but this filter
    # gets called before `login_required`, so we have to handle the case
    # where `current_user` is `nil`.
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

end
