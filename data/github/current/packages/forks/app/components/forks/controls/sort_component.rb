# typed: true
# frozen_string_literal: true

class Forks::Controls::SortComponent < ApplicationComponent
  extend T::Sig
  include Forks::MenuControlsHelper

  OPTIONS = {
    stargazer_counts: "Most starred",
    last_updated: "Recently updated",
    open_issue_counts: "Open issues",
    open_pull_request_counts: "Open pull requests",
  }.freeze

  CONTROL_MENU_TARGET = "selectedSortOption"

  sig { params(path_resolver: Forks::PathResolver, system_args: T.untyped).void }
  def initialize(path_resolver, **system_args)
    @sort_by = path_resolver.options.sort_by.to_sym
    @path_resolver = path_resolver
    @system_args = system_args
  end

  def self.valid_options
    OPTIONS.keys
  end

  private

  attr_reader :system_args, :sort_by

  sig { override.params(option: T.any(String, Symbol)).returns(T::Boolean) }
  def selected?(option)
    option.to_sym == @sort_by
  end

  def option_path(option)
    @path_resolver.next_path(sort_by: option)
  end

  def control_menu_target
    CONTROL_MENU_TARGET
  end
end
