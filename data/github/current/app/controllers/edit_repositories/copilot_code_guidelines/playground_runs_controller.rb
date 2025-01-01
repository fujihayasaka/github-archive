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

      capi = Copilot::User::CopilotApi.new(
        current_user,
        integration_id: CopilotAPI::COPILOT_PR_REVIEWS_INTEGRATION_ID,
        session: nil, # There won't ever be a user session
        real_ip: nil, # Same as above
        token: mint_token,
      )

      log("making request to CAPI")
      resp = capi.create_code_review(
        references: [pr_ref, gl_ref],
        role: "user",
        experiment_headers: { "X-Copilot-Code-Review-Mode": "eval" },
        interaction_id: SecureRandom.uuid,
        interaction_type: "code-review",
        initiator: "user",
      )

      render json: extract_and_format_references(resp)
    else
      render json: { error: guideline_validation_errors.to_sentence }, status: :unprocessable_entity
    end
    rescue CopilotAPI::Error => e
      handle_capi_error(e)
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

  sig { returns(Copilot::DecryptedToken) }
  def mint_token
    new_access = Apps::Privileged.integration(:copilot_pull_request_reviewer)&.grant(current_user, { user_session: user_session })
    access, _ = new_access.redeem(extended_expiry: true)
    Copilot::DecryptedToken.from(access)
  end

  sig do params(
    res: T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess])
  ).returns(T::Array[{ body: String, lineNumber: Integer }])
  end
  def extract_and_format_references(res)
    refs = if res.is_a?(ConcurrentFaraday::FutureResponse)
      res.value.fetch(:copilot_references, [])
    else
      res.fetch(:copilot_references, [])
    end

    refs.each_with_object([]) do |ref, arr|
      next unless ref[:type] == "github.generated-pull-request-comment"

      body = ref.dig(:data, :body)
      line = ref.dig(:data, :line)
      next unless body.present? && line.present?

      arr << { details: body, lineNumber: line }

    end

  end

  def handle_capi_error(err)
    case err
    when CopilotAPI::UnauthorizedError
      render json: { error: "Unauthorized" }, status: :unauthorized
    when CopilotAPI::RAIError
      render json: { error: "The response was filtered due to the content of the request." }, status: :unprocessable_entity
    when CopilotAPI::NotFoundError
      render json: { error: "Not found" }, status: :not_found
    when CopilotAPI::EntityTooLargeError
      render json: { error: "Request entity too large" }, status: :unprocessable_entity
    when CopilotAPI::RateLimitError
      render json: { error: "Rate limited" }, status: :too_many_requests
    when CopilotAPI::RequestError
      render json: { error: "Bad request" }, status: :unprocessable_entity
    else
      render json: { error: "Internal server error" }, status: :internal_server_error
    end
  end
end
