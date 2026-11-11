# typed: strict
# frozen_string_literal: true

class GitHubModels::GetApiKeyComponent < ApplicationComponent
  sig { params(azure_link: T.nilable(String)).void }
  def initialize(azure_link:)
    @azure_link = T.let(azure_link || GitHub.azure_ai_github_url, String)
  end

  sig { returns T.nilable(T::Boolean) }
  def render?
    GitHub.models_enabled?
  end

  private

  sig { returns(String) }
  def token_link
    new_settings_user_access_token_path({
      name: "GitHub Models token",
      description: "Used to call GitHub Models APIs to easily run LLMs: https://docs.github.com/github-models/quickstart#step-2-make-an-api-call",
      user_models: "read"
    })
  end

  sig { returns(String) }
  attr_reader :azure_link
end
