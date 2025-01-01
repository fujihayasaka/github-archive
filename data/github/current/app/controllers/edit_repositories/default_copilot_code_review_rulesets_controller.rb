# typed: true
# frozen_string_literal: true

class EditRepositories::DefaultCopilotCodeReviewRulesetsController < EditRepositories::AbstractCopilotCodeGuidelinesController
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create]

  def create
    # Check if feature flag is enabled
    unless current_repository.feature_flag_enabled?(:copilot_code_review_ruleset_default, default: false)
      render_404
      return
    end

    # Check if repository has a default branch
    default_branch = current_repository.default_branch
    unless default_branch.present?
      flash[:error] = "Repository must have a default branch to create a Copilot ruleset."
      redirect_to repo_repo_settings_copilot_code_review_path
      return
    end

    # Create the ruleset with Copilot-specific configuration
    ruleset_hash = {
      "name" => "Copilot review for default branch",
      "target" => "branch",
      "enforcement" => "active",
      "conditions" => {
        "ref_name" => {
          "include" => ["~DEFAULT_BRANCH"],
          "exclude" => []
        }
      },
      "rules" => [
        {
          "rule_type" => "deletion",
          "parameters" => {}
        },
        {
          "rule_type" => "non_fast_forward",
          "parameters" => {}
        },
        {
          "rule_type" => "copilot_code_review",
          "parameters" => {
            "review_on_push" => false,
            "review_draft_pull_requests" => false
          }
        }
      ]
    }

    begin
      ruleset = RepositoryRulesets::HashParser.to_repository_ruleset(
        current_repository,
        ruleset_hash,
        validate_bypass_actors: false
      )

      if ruleset.save
        flash[:notice] = "Copilot ruleset created successfully."
        redirect_to repo_repo_settings_copilot_code_review_path
      else
        flash[:error] = "Sorry, we couldn't create the Copilot ruleset. Please try again."
        redirect_to repo_repo_settings_copilot_code_review_path
      end
    rescue => e
      flash[:error] = "Sorry, there was a problem creating the Copilot ruleset."
      redirect_to repo_repo_settings_copilot_code_review_path
    end
  end
end
