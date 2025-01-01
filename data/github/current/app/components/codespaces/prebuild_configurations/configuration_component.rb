# typed: true
# frozen_string_literal: true

class Codespaces::PrebuildConfigurations::ConfigurationComponent < ApplicationComponent
  def initialize(form:, repository:, initial_branch_ref: nil, cache_key:, default_branch:, devcontainer_path: nil)
    @form = form
    @repository = repository
    @initial_branch_ref = initial_branch_ref
    @cache_key = cache_key
    @default_branch = default_branch
    @devcontainer_path = devcontainer_path
  end

  private

  attr_reader :form, :repository, :initial_branch_ref, :cache_key, :default_branch, :devcontainer_path
end
