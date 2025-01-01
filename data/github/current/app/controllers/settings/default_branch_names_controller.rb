# typed: true
# frozen_string_literal: true

class Settings::DefaultBranchNamesController < ApplicationController
  include Settings::ControllerMethods
  include BusinessesHelper
  include OrganizationsHelper
  include SettingsHelper
  include TwoFactorHelper

  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access

  stylesheet_bundle :settings
  javascript_bundle :settings
  javascript_bundle :sessions

  def update
    raw_name = params[:default_branch_name]

    if raw_name.blank?
      flash[:error] = "Could not update default branch name preference, " \
        "no branch name given."
    else
      normalized_name = Git::Ref.normalize(raw_name)

      if normalized_name.blank?
        flash[:error] = "Could not update default branch name preference, " \
          "'#{raw_name}' is not a valid branch name."
      elsif normalized_name == current_user.custom_default_new_repo_branch
        flash[:notice] = "Your default branch name is already #{normalized_name}."
      elsif current_user.set_default_new_repo_branch(normalized_name, actor: current_user)
        flash[:notice] = "New repositories you create will use " \
          "'#{normalized_name}' as their default branch name."
      else
        flash[:error] = "Could not set your default branch name preference at this time."
      end
    end

    respond_to do |format|
      format.html do
        redirect_to settings_repositories_path
      end
    end
  end

  def check_name # rubocop:todo GitHub/UseRestfulActions
    raw_name = params[:value]
    normalized_name = Git::Ref.normalize(raw_name) if raw_name

    respond_to do |format|
      format.html_fragment do
        if normalized_name.blank?
          render html: "#{raw_name} is not a valid branch name.",
                 status: :unprocessable_entity,
                 formats: :html
        elsif raw_name != normalized_name
          render html: "Your default branch name will be #{normalized_name}",
                 status: :accepted,
                 formats: :html
        else
          render html: "Your default branch name will be #{normalized_name}"
        end
      end
    end
  end
end
