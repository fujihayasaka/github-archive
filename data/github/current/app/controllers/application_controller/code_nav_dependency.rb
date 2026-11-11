# typed: true
# frozen_string_literal: true

module ApplicationController::CodeNavDependency
  extend T::Helpers
  requires_ancestor { ApplicationController }
  extend ActiveSupport::Concern

  included do
    T.bind(self, T.class_of(ApplicationController))
    helper_method :aleph_code_navigation_viewable?
    helper_method :aleph_code_navigation_available?
  end

  def aleph_code_navigation_available?
    GitHub.aleph_code_navigation_enabled? &&
      !robot? &&
      !mobile? &&
      logged_in? &&
      current_repository &&
      current_repository.alephd_indexing_enabled?
  end

  def aleph_code_navigation_available_for_react?
    GitHub.aleph_code_navigation_enabled? && current_repository
  end

  def aleph_code_navigation_viewable?(lang)
    FeatureFlag.vexi.enabled_or_raise?(BlackbirdSearch::CodeNav.convert_language_name(lang), current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end
end
