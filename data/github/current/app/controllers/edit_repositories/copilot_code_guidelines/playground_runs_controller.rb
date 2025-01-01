# typed: true
# frozen_string_literal: true

# Handles running the coding guideline and test sample from the test playground
class EditRepositories::CopilotCodeGuidelines::PlaygroundRunsController < EditRepositories::AbstractCopilotCodeGuidelinesController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :parse_json_params
  allow_verified_fetch only: [:create]

  def create
    if guideline_validation_errors.none?
      pr_ref = Copilot::PullRequests::CodeReviewReferenceSerializer.new.raw_code_as_copilot_reference(
        repo: current_repository,
        code: playground_params[:sample_code],
      )

      gl_ref = guideline.to_copilot_reference(exclude_file_patterns: true)

      render json: {
        references: [pr_ref, gl_ref],
        integration: CopilotAPI::COPILOT_PR_REVIEWS_INTEGRATION_ID,
        token: mint_token.value,
        api: Copilot::SKUIsolation.for_user(current_user).api.endpoint
      }
    else
      render json: { error: guideline_validation_errors.to_sentence }, status: :unprocessable_entity
    end
  end

  private

  # Validate the guideline. Only caring about validation errors on the user-provided values
  #
  # See: https://github.com/github/copilot-core-productivity/issues/2620
  memoize def guideline_validation_errors
    guideline.validate
    guideline.errors.full_messages_for(:name) + guideline.errors.full_messages_for(:description)
  end

  def playground_params
    params
      .require(:playground)
      .permit(:description, :sample_code)
  end

  sig { returns Copilot::CodingGuideline }
  memoize def guideline
    Copilot::CodingGuideline.new(
      id: 1, # ID required by CAPI; must be positive and non-zero or the guideline gets excluded
      repository: current_repository,
      name: SecureRandom.hex(8), # Generate a fake name for testing so we don't need to worry about name uniqueness
      description: playground_params[:description],
      example_code_violations: playground_params[:example_code_violations],
    )
  end

  sig { returns(Copilot::EncryptedToken) }
  def mint_token
    new_access = Apps::Privileged.integration(:copilot_pull_request_reviewer)&.grant(current_user, { user_session: user_session })
    token, _ = new_access.redeem(extended_expiry: true)

    encrypted = GitHub.dotcom_capi_simple_box.encrypt(token)
    encoded = Base64.urlsafe_encode64(encrypted)

    Copilot::EncryptedToken.from(encoded, expiration: new_access.expires_at)
  end
end
