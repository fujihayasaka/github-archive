# typed: true
# frozen_string_literal: true

class EditRepositories::CopilotCodeGuidelinesController < EditRepositories::AbstractCopilotCodeGuidelinesController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include Repos::RulesHelper

  javascript_bundle :copilot

  before_action :require_code_guideline_feature_enabled, only: [:create, :update, :destroy, :new, :edit]
  before_action :parse_json_params, only: [:create, :update]
  allow_verified_fetch only: [:create, :update]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    ApplicationRecord::Copilot,
    only: [:new, :edit, :index]

  def index
    # This param is passed by the Test Playground react app to show a flash message on the index after successful save.
    if params[:flash].in?(%w[updated created])
      flash.now[:notice] = "Guideline #{params[:flash]}."
    end
    render "edit_repositories/copilot_code_guidelines/index", locals: {
      guidelines: guidelines.limit(Copilot::CodingGuideline::MAX_PER_REPO),
      total_count: total_count,
      enabled_count: enabled_count,
      coding_guideline_feature_enabled: coding_guideline_feature_enabled?,
      feature_is_disabled: feature_disabled?,
    }
  end

  def new
    if total_count >= Copilot::CodingGuideline::MAX_PER_REPO
      flash[:warn] = "You've reached the limit of #{Copilot::CodingGuideline::MAX_PER_REPO} guidelines for this repository."
      redirect_to repo_repo_settings_copilot_code_review_path
    else
      guideline = Copilot::CodingGuideline.new
      render "edit_repositories/copilot_code_guidelines/form", locals: {
        guideline: guideline,
        paths_attributes: guideline.paths_attributes,
        show_tab_bar: !feature_disabled? &&
          current_repository.feature_flag_enabled?(:copilot_code_guidelines_occurrences_page, default: false),
        feature_is_disabled: feature_disabled?
      }
    end
  end

  def edit
    render "edit_repositories/copilot_code_guidelines/form", locals: {
      guideline: guideline,
      paths_attributes: guideline.paths_attributes,
      show_tab_bar: current_repository.feature_flag_enabled?(:copilot_code_guidelines_occurrences_page, default: false),
      feature_is_disabled: feature_disabled?
    }
  end

  def create
    guideline = Copilot::CodingGuideline.new(guideline_params)

    if guideline.save
      head 200
    else
      render json: { errorMessage: guideline.errors.full_messages.to_sentence, errors: guideline.errors }, status: :unprocessable_entity
    end
  end

  def update
    if guideline.update(guideline_params)
      head 200
    else
      render json: { errorMessage: guideline.errors.full_messages.to_sentence, errors: guideline.errors }, status: :unprocessable_entity
    end
  end

  def destroy
    guideline.destroy
    flash[:notice] = "Guideline deleted."

    redirect_to repo_repo_settings_copilot_code_review_path
  end

  private

  def copilot_guideline_id
    params[:id]
  end

  def guideline_params
    params
      .require(:copilot_coding_guideline)
      .permit(:name, :description, :example_code_violations, paths_attributes: [:_destroy, :path, :id])
      .merge(repository_id: current_repository.id)
  end
end
