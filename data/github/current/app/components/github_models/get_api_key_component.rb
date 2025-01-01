# typed: strict
# frozen_string_literal: true

class GitHubModels::GetApiKeyComponent < ApplicationComponent
  sig { params(azure_link: T.nilable(String)).void }
  def initialize(azure_link:)
    @azure_link = T.let(azure_link || GitHub.azure_ai_github_url, String)
  end

  sig { returns(T::Boolean) }
  def render?
    !GitHub.enterprise?
  end

  private

  sig { returns(String) }
  attr_reader :azure_link
end
