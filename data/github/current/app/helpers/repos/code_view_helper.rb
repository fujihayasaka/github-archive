# typed: true
# frozen_string_literal: true

module Repos::CodeViewHelper
  extend T::Helpers

  abstract!

  # Is the React version of Repos (tree / blob / overview / commits / branches) enabled?
  #
  # By default, controlled by flipper on GitHub.com and ENTERPRISE_REACT_CODE_VIEW_ENABLED env var on GHES.
  #
  # Returns boolean.
  sig { returns(T::Boolean) }
  def code_view_enabled?
    FeatureFlag.vexi.enabled_or_raise?(:react_code_view_enabled) || GitHub.enterprise? # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  alias react_branches_enabled? code_view_enabled?
  alias react_commits_enabled? code_view_enabled?

  # Are symbols enabled for the blob in Code View?
  # For symbols to be enabled, we need Aleph and Blackbird support.
  #
  # By default, true for GitHub.com / Proxima, disabled on GHES.
  # Returns boolean.
  sig { returns(T::Boolean) }
  def symbols_enabled?
    !GitHub.enterprise?
  end
end
