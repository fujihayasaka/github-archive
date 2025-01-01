# typed: true
# frozen_string_literal: true

class Codespaces::PrebuildConfigurations::RunnerGroupComponent < ApplicationComponent
  def initialize(form:, repo:, runner_group_options:)
    @form = form
    @repo = repo
    @runner_group_options = runner_group_options
  end

  def select_arguments
    {
      name: "larger_runner",
      label: "Actions Runner",
      visually_hide_label: true,
      size: :medium,
    }
  end

  private

  attr_reader :form, :repo, :runner_group_options
end
