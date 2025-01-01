# typed: strict
# frozen_string_literal: true
class Repositories::SuggestedWorkflows::CardComponent < ApplicationComponent
  extend T::Sig

  sig { returns RepositoryActions::Onboarding::Template }
  attr_reader :template

  sig { returns Repository }
  attr_reader :repository

  sig { returns T::Hash[T.any(Symbol, String), T.untyped] }
  attr_reader :button_data

  sig { returns String }
  attr_reader :button_text

  sig { returns T::Hash[Symbol, T.untyped] }
  attr_reader :system_arguments

  sig do
    params(
      template: RepositoryActions::Onboarding::Template,
      repository: Repository,
      branch_or_tag_name: T.nilable(String),
      button_data: T::Hash[T.any(Symbol, String), T.untyped],
      button_text: String,
      configure_path: T.nilable(String),
      system_arguments: T.untyped
    ).void
  end
  def initialize(template:, repository:, branch_or_tag_name: nil, button_data: {}, button_text: "Configure", configure_path: nil, **system_arguments)
    @template = template
    @repository = repository
    @branch_or_tag_name = T.let(branch_or_tag_name || repository.default_branch, String)
    @button_data = button_data
    @button_text = button_text
    @configure_path = configure_path
    @system_arguments = system_arguments
    @system_arguments[:mb] ||= 2
    @system_arguments[:p] ||= 3
    @system_arguments[:border] = true unless system_arguments[:border]
    @system_arguments[:border_radius] ||= 2
  end

  sig { returns String }
  def configure_path
    return @configure_path unless @configure_path.nil?

    @configure_path = new_file_path(
      @repository.owner,
      @repository,
      @branch_or_tag_name,
      filename: @template.default_file_name,
      workflow_template: @template.id
    )
  end

  sig { returns(String) }
  def byline
    "By #{template.creator_name.presence || repository.owner&.safe_profile_name}"
  end
end
