# typed: true
# frozen_string_literal: true

class EditRepositories::CopilotCodeGuidelinesController < AbstractRepositoryController
  before_action :require_feature_flag
  before_action :ensure_admin_access
  before_action :require_can_change_copilot_enterprise_settings

  javascript_bundle :copilot

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
    guidelines = Copilot::CodingGuideline
      .where(repository: current_repository)
      .limit(Copilot::CodingGuideline::MAX_PER_REPO)

    render "edit_repositories/copilot_code_guidelines/index", locals: {
      guidelines:,
    }
  end

  def new
    render "edit_repositories/copilot_code_guidelines/new", locals: {
      coding_guideline: Copilot::CodingGuideline.new,
      suggestions: suggestions
    }
  end

  def edit
    coding_guideline = Copilot::CodingGuideline.where(repository: current_repository).find(params[:id])
    render "edit_repositories/copilot_code_guidelines/edit", locals: {
      coding_guideline: coding_guideline,
      suggestions: suggestions
    }
  end

  def create
    guideline = Copilot::CodingGuideline.new(guideline_params)

    if guideline.save
      flash[:notice] = "Guideline created."
      redirect_to copilot_code_guidelines_path
    else
      flash[:error] = guideline.errors.full_messages.to_sentence

      render "edit_repositories/copilot_code_guidelines/new", locals: {
        coding_guideline: guideline,
        suggestions: suggestions
      }
    end
  end

  def update
    guideline = Copilot::CodingGuideline.where(repository: current_repository).find(params[:id])

    if guideline.update(guideline_params)
      flash[:notice] = "Guideline updated."
      redirect_to copilot_code_guidelines_path
    else
      flash[:error] = guideline.errors.full_messages.to_sentence

      render "edit_repositories/copilot_code_guidelines/edit", locals: {
        coding_guideline: guideline,
        suggestions: suggestions
      }
    end
  end

  def destroy
    guideline = Copilot::CodingGuideline.where(repository: current_repository).find(params[:id])

    guideline.destroy
    flash[:notice] = "Guideline deleted."

    redirect_to copilot_code_guidelines_path
  end

  private

  def guideline_params
    params
      .require(:copilot_coding_guideline)
      .permit(:name, :description, :example_code_violations, paths_attributes: [:_destroy, :path, :id])
      .merge(repository_id: current_repository.id)
  end

  sig { void }
  def require_feature_flag
    render_404 unless user_or_global_feature_enabled?(:copilot_coding_guidelines)
  end

  sig { void }
  def require_can_change_copilot_enterprise_settings
    render_404 unless Copilot::Organization.new(current_repository.owner).can_use_copilot_enterprise_features?
  end

  # List of suggestions that user's can click to get ideas for custom instructions
  #
  # The key is the text that will appear in the button. The value is the full
  # text that will be inserted into the textarea.
  def suggestions
    {
      "Variable names": "Prefer variables that are <concise/more than one letter>.",
      "Correct English": "Ensure correct spelling.",
      "Prefer libraries": "Prefer to use <library> instead of <library to avoid>.",
    }
  end
end
