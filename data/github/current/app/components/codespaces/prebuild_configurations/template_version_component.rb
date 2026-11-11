# typed: true
# frozen_string_literal: true

class Codespaces::PrebuildConfigurations::TemplateVersionComponent < ApplicationComponent
  def initialize(form:, repo:, maximum_template_versions:)
    @form = form
    @repo = repo
    @maximum_template_versions = maximum_template_versions
  end

  private

  attr_reader :repo, :maximum_template_versions, :form
end
