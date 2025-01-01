# typed: true
# frozen_string_literal: true

class Forks::Controls::SaveDefaultOptionsComponent < ApplicationComponent
  extend T::Sig
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
    # Checking for feature flag last to avoid DB query that isn't otherwise
    # needed, unless we really have to.
    logged_in? && @path_resolver.options.feature_enabled?(:user_default_options)
  end
end
