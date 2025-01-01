# typed: true
# frozen_string_literal: true

class Forks::Controls::SaveDefaultOptionsComponent < ApplicationComponent
  delegate :current_user, to: :helpers
  delegate :forks_default_options_path, to: :helpers

  ACTIVE_VALUE = "Save Defaults"
  DISABLED_VALUE = "Defaults Saved"

  sig { params(path_resolver: Forks::PathResolver).void }
  def initialize(path_resolver)
    @path_resolver = path_resolver
  end

  private

  def action_path
    forks_default_options_path(@path_resolver.repo_owner_display_login, @path_resolver.repo_name)
  end

  def allow_submit?
    !@path_resolver.options.persisted?
  end

  def render?
    logged_in?
  end
end
