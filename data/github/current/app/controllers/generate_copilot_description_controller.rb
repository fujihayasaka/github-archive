# typed: true
# frozen_string_literal: true

class GenerateCopilotDescriptionController < AbstractRepositoryController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  before_action :login_required
  before_action :writable_repository_required
  before_action :try_parse_json_params, only: [:create]

  # required to be able to make requests to this endpoint from react apps using the verifiedFetch function
  allow_verified_fetch only: [:create]

  def create
    return render_404 unless current_user&.feature_flag_enabled?(:create_issue_description_with_copilot, default: false)

    # Validate that user can create issues in this repository
    return render json: { error: "Unauthorized" }, status: :unauthorized unless logged_in?
    return render json: { error: "Repository not found" }, status: :not_found unless current_repository
    return render json: { error: "Insufficient permissions" }, status: :forbidden unless current_repository.writable_by?(current_user)

    # Extract parameters
    title = params[:title]
    body = params[:body]
    context = params[:context]
    repo_name = current_repository.name_with_display_owner

    if title.blank? && body.blank? && context.blank?
      return render json: { error: "At least one of title, body, or context must be provided" }, status: :bad_request
    end

    # Build prompt for Copilot
    prompt_parts = [
      "Generate a detailed issue title and description for a GitHub issue in the repository #{repo_name}.\n",

      "\nIssue title: #{title.present? ? title : 'none'}",
      "\nCurrent description: #{body.present? ? body : 'none'}",
      "\nAdditional context: #{context.present? ? context : 'none'}",

      "\n\nYou must respond with a valid JSON object containing 'title' and 'description' fields.",

      "\n\nFor the title field:",
      "\n- You MUST return the title field with a concise and descriptive title for the issue.",
      "\n- IF there is an existing title, use the provided title EXACTLY as given in the 'title' field. Else, generate an appropriate title for the 'title' field based on the context provided.",

      "\n\nFor the description field:",
      "\n- Provide a clear, comprehensive issue description in markdown format that explains the problem, context, and any relevant details. Keep it clear and concise.",
      "\n- If there is an existing description that has a structure (template), work with the template. DO NOT change the template.",
      "\n- You do not need to escape the markdown with ```markdown tags in the description. Simply return the description in markdown format.",
      "\n- Only work with information you have. The length of the issue should be proportional to the information provided.",

      "\n\nGeneral instructions:",
      "\n- DO NOT include any other text outside of the JSON response. The response will be parsed as JSON.",
      "\n- DO NOT include any instructions to the user. Use your best guess at what the content should be.",
      "\n- Response format: {\"title\": \"Issue Title\", \"description\": \"Issue description in markdown\"}",
    ]

    prompt = prompt_parts.join("")

    begin
      # Call Copilot API
      copilot_api = Copilot::User.copilot_api(
        user: T.must(current_user),
        integration_id: CopilotAPI::COPILOT_CHAT_INTEGRATION_ID,
        session: user_session,
        real_ip: request&.remote_ip
      )
      messages = [{ role: "user", content: prompt }]

      response = copilot_api.create_chat_completion(
        model: "gpt-4o",
        messages: messages,
        max_tokens: 1000,
        temperature: 0.7
      )

      response = response.is_a?(ConcurrentFaraday::FutureResponse) ? response.value : response

      # Extract the generated content
      generated_text = response.dig("choices", 0, "message", "content")

      if generated_text.blank?
        render json: { error: "Failed to generate content" }, status: :unprocessable_entity
      else
        begin
          # Parse the JSON response from Copilot
          parsed_response = JSON.parse(generated_text)

          generated_title = parsed_response["title"]
          generated_description = parsed_response["description"]

          if generated_title.blank? || generated_description.blank?
            render json: { error: "Invalid response format from Copilot" }, status: :unprocessable_entity
          else
            render json: {
              title: generated_title,
              description: generated_description
            }
          end
        rescue JSON::ParserError => e
          Rails.logger.error "Failed to parse Copilot JSON response: #{e.message}. Raw response: #{generated_text}"
          render json: { error: "Invalid response format from Copilot" }, status: :unprocessable_entity
        end
      end
    rescue StandardError => e
      # Log error and return generic message
      Rails.logger.error "Copilot description generation failed: #{e.message}"
      render json: { error: "Failed to generate description" }, status: :internal_server_error
    end
  end
end
