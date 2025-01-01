# typed: true
# frozen_string_literal: true

class Copilot::NlGitHubSearchCompletionsController < ApplicationController

  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  allow_verified_fetch only: [:create]
  before_action :try_parse_json_params, only: [:create]
  before_action :login_required
  before_action :require_feature_enabled

  class InvalidSearchQueryError < StandardError; end

  sig { void }
  def create
    respond_to do |wants|
      wants.json do
        prompt = ::Copilot::Prompt::NaturalLanguageSearch.prompts(query: query).first
        if prompt.nil?
          raise InvalidSearchQueryError.new("Could not perform search with an empty query. Please contact our support team for more details.")
        end

        result = current_user.copilot_api(integration_id: CopilotAPI::COPILOT_CHAT_INTEGRATION_ID, token: token).create_chat_completion(
          model: "gpt-3.5-turbo",
          messages: prompt.messages.map(&:to_h),
          max_tokens: prompt.expected_response_tokens.max,
          temperature: 0.2,
          stop: []
        )

        render json: {
          query: result.dig("choices", 0, "message", "content")
        }
      rescue CopilotAPI::RateLimitError => e
        render json: { error: e }, status: :too_many_requests
      end
    end
  end

  private

  sig { returns T.nilable(Copilot::DecryptedToken) }
  def token
    GitHub.decode_and_decrypt_capi_token(request&.headers[CopilotAPI::TOKEN_HEADER])
  end

  sig { void }
  def require_feature_enabled
    render_404 unless current_user.feature_enabled?(:copilot_natural_language_github_search)
  end

  def resource_for_conditional_access
    current_user
  end

  def target_for_conditional_access
    current_user
  end

  sig { returns(String) }
  def query
    params[:query]
  end
end
