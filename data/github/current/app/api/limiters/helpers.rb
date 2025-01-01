# typed: true
# frozen_string_literal: true

module Api::Limiters::Helpers
  extend T::Helpers

  requires_ancestor { GitHub::Limiter }

  INTERNAL_AUTHENTICATION_FINGERPRINT = "github.internal_authentication_fingerprint".freeze

  def fingerprint(request, omit_ip: false)
    get_fingerprint(request.env, omit_ip: omit_ip).to_s
  end

  def auth_type(request, omit_ip: false)
    get_fingerprint(request.env, omit_ip: omit_ip).auth_type
  end

  def integration_actor?(request, omit_ip: false)
    get_fingerprint(request.env, omit_ip: omit_ip).integration_actor?
  end

  def integration_slug(request, omit_ip: false)
    get_fingerprint(request.env, omit_ip: omit_ip).integration_actor_slug
  end

  def http_user_agent(request)
    user_agent = request.env[GitHub::Middleware::Constants::HTTP_USER_AGENT]
    normalize_user_agent(user_agent) if user_agent
  end

  private

  def get_fingerprint(env, omit_ip: false)
    if omit_ip
      env[INTERNAL_AUTHENTICATION_FINGERPRINT] ||= Api::RequestAuthenticationFingerprint.from(env, omit_ip: omit_ip)
    else
      Api::Middleware::RequestAuthenticationFingerprint.get(env)
    end
  end

  def normalize_user_agent(user_agent)
    parts = user_agent.split("/")
    normalize_octokit(user_agent) || normalize_turboghas(parts) || normalize_github_prefix(parts) || parts.first # Fallback including: heaven/ab2a5b88 -> heaven, launch/production -> launch, opaque/staging/cc79954 -> opaque/staging, go-github -> go-github
  end

  # Example: octokit-request.js/5.6.3 Node.js/20.11.1 (linux; x64) -> octokit-request.js/5.6.3 Node.js/20.11.1
  def normalize_octokit(user_agent)
    user_agent.sub(/ \(.*\)/, "") if user_agent.start_with?("octokit")
  end

  # Example: github/turboghas#turboghas@873d6dcf5abdb13918a7405f52b7a0422356949c (#code-scanning) -> turboghas#turboghas
  def normalize_turboghas(parts)
    parts.last.split("@").first if parts.length == 2 && parts.last.start_with?("turboghas")
  end

  # Example: github/dependabot-api (Octokit Ruby Gem 6.1.1) -> dependabot-api (Octokit Ruby Gem 6.1.1)
  def normalize_github_prefix(parts)
    parts.last if parts.length == 2 && parts.first == "github"
  end
end
