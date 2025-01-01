# typed: true
# frozen_string_literal: true

class GitHubModels::Documentation::DependenciesComponent < ApplicationComponent
  def initialize(sdk:, language:)
    @sdk = sdk
    @language = language
  end

  def template_path
    "dependencies/#{@language}/#{@sdk}_sdk"
  end
end
