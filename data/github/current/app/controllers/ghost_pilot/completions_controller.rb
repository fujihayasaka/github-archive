# typed: true
# frozen_string_literal: true

class GhostPilot::CompletionsController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :feature_flags_required
  before_action :copilot_enterprise_seat_required
  before_action :valid_editor_version_required, except: [:feedback]

  ALLOWED_USER_AGENT_REGEX = /\AGitHub(GhostPilot|WorkspaceEditor)\/[\.\d]+\z/

  allow_verified_fetch only: [:create, :token]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:token, :feedback]

  def token # rubocop:todo GitHub/UseRestfulActions
    token, domain = auth_token_and_domain
    if token
      render json: { token:, completions_url: Copilot::Completions.code_completion_url(domain, engine: proxy_model) }
    else
      head :forbidden
    end
  end

  def create
    token, domain = auth_token_and_domain
    if token
      render json: Copilot::Completions.prompt_code_completion(
        body: request.body.read,
        auth_token: token,
        domain:,
        user_agent: request.headers["Editor-Version"],
        engine: proxy_model
      )
    else
      head :forbidden
    end
  end

  def feedback # rubocop:todo GitHub/UseRestfulActions
    repo = Repositories::Public.get_active_or_deleted!(params.require(:repository_id))
    return head(:not_found) unless repo.visible_and_readable_by?(current_user)

    session_id = feedback_session_id

    feedback_url = repo_completion_feedback_session_url(repo.owner, repo, session_id:)
    render json: {
      feedback_url:,
      feedback_auth_token: authenticity_token_for(feedback_url, method: :put),
      session_id:,
    }
  end

  private

  def feedback_session_id
    cache_key = "completion_feedback_#{current_user.id}_#{params[:repository_id]}"
    cached_session_id = Codespaces::Kv.store.get(cache_key).value { nil }
    return cached_session_id if cached_session_id

    new_session_id = SecureRandom.uuid
    ActiveRecord::Base.connected_to(role: :writing) do
      Codespaces::Kv.store.set(cache_key, new_session_id, expires: 12.hours.from_now)
    end
    new_session_id
  end

  # TODO: This should be moved into an appropriate service's KV once this isn't an experiment
  # owned by the Codespaces MX team.
  def auth_token_and_domain
    cache_key = "#{current_user.id}_#{request.headers["Editor-Version"]}_completion_token_and_domain"
    cached_token = Codespaces::Kv.store.get(cache_key).value { nil }
    return cached_token.split(", ") if cached_token

    domain = Copilot::SKUIsolation.for_user(current_user).proxy.endpoint

    # Dev-only, our dev server can't issue a valid token for prod so auth via internal API instead
    if Rails.env.development?
      new_token = fetch_internal_api_token
      cache_token(cache_key, "#{new_token}, #{domain}") if new_token
      return [new_token, domain]
    end

    authorizer = Copilot::Authorizer.new(copilot_user, GitHub.context)
    envelope = Copilot::Envelope.new(authorizer, envelope_headers).envelope
    if envelope[:error_details] # ErrorEnvelope
      GitHub.dogstats.increment("copilot.completion.bad_envelope", tags: ["reason:#{envelope[:error_details][:notification_id]}"])
      nil
    else
      new_token = envelope[:token]
      cache_token(cache_key, "#{new_token}, #{domain}", authorizer) if new_token
      [new_token, domain]
    end
  end

  sig { returns T::Hash[Symbol, String] }
  def envelope_headers
    { # TODO: Add :real_ip, :asn
      editor_version: request.headers["Editor-Version"],
    }
  end

  def valid_editor_version_required
    render_404 unless request.headers["Editor-Version"]&.match?(ALLOWED_USER_AGENT_REGEX)
  end

  # Used in dev only.

  def fetch_internal_api_token
    uri = URI("https://api.github.com/copilot_internal/v2/token")
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "bearer #{ENV["GITHUB_TOKEN"]}"
    request["Editor-Version"] = editor_version_for_user

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end
    new_token = JSON.parse(response.body)["token"]
  end

  def cache_token(key, token, authorizer = nil, headers = nil)
    expires = 25.minutes.from_now
    ActiveRecord::Base.connected_to(role: :writing) do
      Codespaces::Kv.store.set(key, token, expires:)
    end
    if authorizer
      Copilot::Instrumenter.instrument_token_generated(
        copilot_user,
        expires.to_i,
        authorizer&.access_type,
        envelope_headers,
        authorizer&.organization_list,
      )
    end
    token
  end

  def feature_flags_required
    render_404 unless current_user&.feature_preview_enabled?(:ghost_pilot_pr_autocomplete) ||
      current_user&.feature_enabled?(:hadron_terminal_completions)
  end

  sig { returns Copilot::User }
  memoize def copilot_user
    T.must_because(current_copilot_user) { "#login_required ensures non-nil" }
  end

  def copilot_enterprise_seat_required
    render_404 unless copilot_user.has_cfe_access?
  end

  def resource_for_conditional_access
    current_user || :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  def target_for_conditional_access
    current_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  # Used in dev only.
  def editor_version_for_user
    if current_user.feature_enabled?(:ghost_pilot_vnext)
      GhostPilot::SuggestionsComponent::NEXT_VERSION
    else
      GhostPilot::SuggestionsComponent::VERSION
    end
  end

  sig { returns Copilot::Completions::Model }
  def proxy_model
    if current_user.feature_enabled?(:copilot_completion_4o_mini) && current_user.feature_enabled?(:ghost_pilot_vnext)
      Copilot::Completions::Model::GPT4oMini
    else
      Copilot::Completions::Model::GPT35Turbo
    end
  end
end
