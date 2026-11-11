# typed: true
# frozen_string_literal: true

class EditRepositories::DefaultCopilotCodeReviewRulesetsController < EditRepositories::AbstractCopilotCodeGuidelinesController
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create]

  BASE_RULESET_NAME = "Copilot review for default branch"

  class NoAvailableRulesetNameError < StandardError; end

  def create
    # Check if repository has a default branch
    default_branch = current_repository.default_branch
    unless default_branch.present?
      GitHub.dogstats.increment("ccr_default_ruleset_created", tags: ["status:error"])
      flash[:error] = "Repository must have a default branch to create a Copilot ruleset."
      redirect_to repo_repo_settings_copilot_code_review_path
      return
    end

    begin
      # Create the ruleset with Copilot-specific configuration
      ruleset_hash = {
        "name" => unique_ruleset_name,
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

      ruleset = RepositoryRulesets::HashParser.to_repository_ruleset(
        current_repository,
        ruleset_hash,
        validate_bypass_actors: false
      )

      if ruleset.save
        GitHub.dogstats.increment("ccr_default_ruleset_created", tags: ["status:success"])
        flash[:notice] = "Copilot ruleset created successfully."
        redirect_to repo_repo_settings_copilot_code_review_path
      else
        GitHub.dogstats.increment("ccr_default_ruleset_created", tags: ["status:error"])
        flash[:error] = "Sorry, we couldn't create the Copilot ruleset. Please try again."
        redirect_to repo_repo_settings_copilot_code_review_path
      end
    rescue NoAvailableRulesetNameError => e
      GitHub.dogstats.increment("ccr_default_ruleset_created", tags: ["status:error"])
      flash[:error] = "Sorry, we couldn't create the Copilot ruleset because the maximum number of default-branch Copilot rulesets has been reached."
      redirect_to repo_repo_settings_copilot_code_review_path
    rescue => e
      GitHub.dogstats.increment("ccr_default_ruleset_created", tags: ["status:error"])
      flash[:error] = "Sorry, there was a problem creating the Copilot ruleset."
      redirect_to repo_repo_settings_copilot_code_review_path
    end
  end

  private

  def unique_ruleset_name
    existing_names = current_repository.rulesets.where("name LIKE ?", "#{BASE_RULESET_NAME}%").pluck(:name).to_set
    return BASE_RULESET_NAME unless existing_names.include?(BASE_RULESET_NAME)

    (2..RepositoryRuleset::RULESET_LIMIT).each do |i|
      candidate = "#{BASE_RULESET_NAME} #{i}"
      return candidate unless existing_names.include?(candidate)
    end

    raise NoAvailableRulesetNameError, "No available unique name for default Copilot code review ruleset"
  end
end
