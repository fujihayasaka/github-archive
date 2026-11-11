# typed: true
# frozen_string_literal: true

class GitHubUI::PreviewsController < ApplicationController
  def create
    return render_404 unless current_user&.employee? || Rails.env.development?

    sha = params[:_ui_sha]

    if sha.blank? || !GitHubUI::PreviewManifestStore.allowed?(git_sha: sha)
      flash[:error] = "The provided SHA doesn't have a preview available. Please deploy the SHA to the preview environment first."
    else
      flash[:success] = "Now using SHA #{sha}."
    end

    redirect_back(fallback_location: "/")
  end

  private

  def target_for_conditional_access
    logged_in? ? current_user : :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def resource_for_conditional_access
    logged_in? ? current_user : :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end
end
