# typed: true
# frozen_string_literal: true

# Generates a code sample for a coding guideline
class EditRepositories::CopilotCodeGuidelines::SampleCodeGenerationsController < EditRepositories::AbstractCopilotCodeGuidelinesController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :parse_json_params
  allow_verified_fetch only: [:create]

  def create
    if description_error_message
      render json: { error: description_error_message }, status: :unprocessable_entity
    else
      code_sample = generate_code_sample(
        entry_point: :edit_repositories_copilot_code_guidelines_sample_code_generations_controller_create
      ).dig("choices", 0, "message", "content")
      render json: { sampleCode: code_sample }
    end
  rescue CopilotAPI::Error => e
    handle_capi_error(e)
  end

  private

  memoize def description_error_message
    if params[:description].blank?
      "Description can't be blank"
    elsif params[:description].to_s.size > Copilot::CodingGuideline::PROMPT_CHAR_LIMIT
      "Description is too long (maximum is #{Copilot::CodingGuideline::PROMPT_CHAR_LIMIT} characters)"
    end
  end

  def generate_code_sample(entry_point:)
    if @generate_code_sample.is_a?(Hash) && @generate_code_sample.key?(entry_point)
      return @generate_code_sample[entry_point]
    end

    @generate_code_sample ||= {}

    @generate_code_sample[entry_point] =
      capi(entry_point:).create_chat_completion(
        model: "gpt-4o-2024-05-13",
        messages: [{ role: "user", content: prompt }],
        max_tokens: 1_000,
        temperature: 0.4,
        stop: []
      )
  end

  def prompt
    <<-TEXT
    You are an AI assistant tasked with generating sample code to test coding
    guideline rules. You will be given a description of a coding guideline rule
    that is typically checked during code reviews. Your job is to create sample
    code that demonstrates both compliance and violation of this rule.

    ## Input

    You will receive a description of a coding guideline rule that will be used
    to review code. The description will be provided in a
    <code-guideline-description> tag. This rule describes a specific coding
    practice or pattern that should be followed or avoided.

    ## Task

    - Analyze the given <code-guideline-description>.
    - Ensure the snippets are minimal and focused on demonstrating the specific rule.
    - Use appropriate comments to explain key parts of the code

    ## Output Format

    Provide a code sample following these rules:

    - The sample code should violate the description <code-guideline-description>
    - The code should be complete. Always include a full and complete code sample and do not omit anything.
    - Do not wrap code in markdown code blocks. Only output code.
    - Only show code. Do not include explanations.
    - Remember to adapt your code examples to the specific programming language and context implied by the given guideline.
    - Never include comments about which line is in violation of the guideline. The violation should be clear from the code itself.
    - Never include comments about violations or whether code is correct or in compliance with the guideline.
    - You may include a comment explaining what the code is doing, but this is not required.
    - If guideline is unclear, respond with "I'm sorry, I'm not sure what the code should look like. Please provide more detail in the guideline description."

    <code-guideline-description>
    #{params.fetch(:description)}
    </code-guideline-description>
    TEXT
  end

  sig { params(entry_point: Symbol).returns(Copilot::User::CopilotApi) }
  def capi(entry_point:)
    current_user.copilot_api(integration_id: CopilotAPI::COPILOT_CHAT_INTEGRATION_ID, token: copilot_api_token(entry_point:))
  end

  sig { params(entry_point: Symbol).returns(Copilot::EncryptedToken) }
  def copilot_api_token(entry_point:)
    helpers.copilot_mint_token(user_session, entry_point:)
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
      render json: { error: "Response was too large" }, status: :unprocessable_entity
    when CopilotAPI::RateLimitError
      render json: { error: "Rate limited" }, status: :too_many_requests
    else
      render json: { error: "Internal server error" }, status: :internal_server_error
    end
  end
end
