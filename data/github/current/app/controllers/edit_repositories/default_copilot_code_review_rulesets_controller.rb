# typed: true
# frozen_string_literal: true

class EditRepositories::DefaultCopilotCodeReviewRulesetsController < AbstractRepositoryController
  include ApplicationController::VerifiedFetchDependency

  before_action :ensure_admin_access
  allow_verified_fetch only: [:create]

  BASE_RULESET_NAME = "Copilot review for default branch"

  class NoAvailableRulesetNameError < StandardError; end

  def create
    # Check if repository has a default branch
    default_branch = current_repository.default_branch
    unless default_branch.present?
      GitHub.dogstats.increment("ccr_default_ruleset_created", tags: ["status:error"])
      message = "Repository must have a default branch to create a Copilot ruleset."
      respond_to do |format|
        format.html do
          flash[:error] = message
          redirect_to repository_rulesets_redirect_path
        end
        format.json { render json: { error: message }, status: :unprocessable_entity }
      end
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

      ruleset = RepositoryRulesets::HashParser.to_ruleset(
        Repositories.domain.rulesets,
        current_repository,
        ruleset_hash,
        validate_bypass_actors: false
      )

      if ruleset.save
        GitHub.dogstats.increment("ccr_default_ruleset_created", tags: ["status:success"])
        respond_to do |format|
          format.html do
            flash[:notice] = "Copilot ruleset created successfully."
            redirect_to repository_rulesets_redirect_path
          end
          format.json { render json: { url: repository_rulesets_redirect_path }, status: :ok }
        end
      else
        GitHub.dogstats.increment("ccr_default_ruleset_created", tags: ["status:error"])
        message = "Sorry, we couldn't create the Copilot ruleset. Please try again."
        respond_to do |format|
          format.html do
            flash[:error] = message
            redirect_to repository_rulesets_redirect_path
          end
          format.json { render json: { error: message }, status: :unprocessable_entity }
        end
      end
    rescue NoAvailableRulesetNameError => e
      GitHub.dogstats.increment("ccr_default_ruleset_created", tags: ["status:error"])
      message = "Sorry, we couldn't create the Copilot ruleset because the maximum number of default-branch Copilot rulesets has been reached."
      respond_to do |format|
        format.html do
          flash[:error] = message
          redirect_to repository_rulesets_redirect_path
        end
        format.json { render json: { error: message }, status: :unprocessable_entity }
      end
    rescue => e
      GitHub.dogstats.increment("ccr_default_ruleset_created", tags: ["status:error"])
      message = "Sorry, there was a problem creating the Copilot ruleset."
      respond_to do |format|
        format.html do
          flash[:error] = message
          redirect_to repository_rulesets_redirect_path
        end
        format.json { render json: { error: message }, status: :internal_server_error }
      end
    end
  end

  private

  def repository_rulesets_redirect_path
    repository_rulesets_path(current_repository.owner, current_repository)
  end

  def unique_ruleset_name
    existing_names = current_repository.rulesets.where("name LIKE ?", "#{BASE_RULESET_NAME}%").pluck(:name).to_set
    return BASE_RULESET_NAME unless existing_names.include?(BASE_RULESET_NAME)

    (2..Repositories.domain.rulesets.ruleset_limit(current_repository)).each do |i|
      candidate = "#{BASE_RULESET_NAME} #{i}"
      return candidate unless existing_names.include?(candidate)
    end

    raise NoAvailableRulesetNameError, "No available unique name for default Copilot code review ruleset"
  end
end
