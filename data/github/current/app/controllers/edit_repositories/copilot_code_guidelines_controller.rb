# typed: true
# frozen_string_literal: true

class EditRepositories::CopilotCodeGuidelinesController < EditRepositories::AbstractCopilotCodeGuidelinesController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  javascript_bundle :copilot

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
      show_auto_review_hint: show_auto_review_hint?
    }
  end

  def new
    if total_count >= Copilot::CodingGuideline::MAX_PER_REPO
      flash[:warn] = "You've reached the limit of #{Copilot::CodingGuideline::MAX_PER_REPO} guidelines for this repository."
      redirect_to copilot_code_guidelines_path
    else
      guideline = Copilot::CodingGuideline.new
      render "edit_repositories/copilot_code_guidelines/form", locals: {
        guideline: guideline,
        paths_attributes: guideline.paths_attributes,
        show_tab_bar: current_repository.feature_enabled?(:copilot_code_guidelines_occurrences_page)
      }
    end
  end

  def edit
    render "edit_repositories/copilot_code_guidelines/form", locals: {
      guideline: guideline,
      paths_attributes: guideline.paths_attributes,
      show_tab_bar: current_repository.feature_enabled?(:copilot_code_guidelines_occurrences_page)
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

    redirect_to copilot_code_guidelines_path
  end

  private

  # Private: returns true if the banner should be shown that lets users know they can enable automatic code review.
  def show_auto_review_hint?
    return false if current_user.dismissed_notice?(:copilot_coding_guidelines_auto_review_disabled)

    !has_auto_reviews_enabled?
  end

  # Private: returns true if the current repo has automatic code reviews enabled
  #
  # This is used to show a hint banner if auto reviews have not been set up for Copilot Code Review
  def has_auto_reviews_enabled?
    # This will load rulesets defined on repo and rulesets defined on its parents that affect this repo (e.g. the owning org)
    RepositoryRuleset.load_for(source: current_repository, targets: ["branch"], include_parents: true).any? do |ruleset|
      ruleset.rule_configurations.any? do |rule|
        rule.rule_type == "pull_request" && rule.param("automatic_copilot_code_review_enabled")
      end
    end
  end

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
