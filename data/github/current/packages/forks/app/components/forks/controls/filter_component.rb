# typed: true
# frozen_string_literal: true

class Forks::Controls::FilterComponent < ApplicationComponent
  include Forks::MenuControlsHelper

  CONTROL_MENU_TARGET = "selectedRepositoryTypeOptions"

  OPTIONS = {
    active: "Active",
    inactive: "Inactive",
    network: "Network",
    archived: "Archived",
    starred: "Starred",
  }.freeze

  HELP_TEXT = {
    active: "Repositories with push activity",
    inactive: "Repositories with no push activity",
    network: "Forks of other forks",
    archived: "Archived repositories",
    starred: "Repositories with at least 1 star",
  }.freeze

  sig { params(path_resolver: Forks::PathResolver, system_args: T.untyped).void }
  def initialize(path_resolver, **system_args)
    @path_resolver = path_resolver
    @control_state = path_resolver.options
    @system_args = system_args
  end

  def self.valid_options
    OPTIONS.keys
  end

  private

  attr_reader :system_args, :path_resolver, :control_state

  sig { override.params(option: Symbol).returns(String) }
  def option_path(option)
    directive = "include_#{option}"
    # Invert the existing state
    directive_enabled = path_resolver.options.include.exclude?(option)
    path_resolver.next_path(directive => directive_enabled)
  end

  sig { override.params(option: Symbol).returns(T::Boolean) }
  def selected?(option)
    path_resolver.options.include.include?(option)
  end

  sig { override.returns(String) }
  def control_menu_target
    CONTROL_MENU_TARGET
  end
end
