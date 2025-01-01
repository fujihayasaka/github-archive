# typed: true
# frozen_string_literal: true

module ApplicationController::CodespaceTagActionDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))
    preload_features [:codespaces_automated_testing]

    before_action :tag_automated_testing
  end

  # Tag requests involving automated test users so that they can be excluded
  # from metrics. Counterpart to Api::App::CodespacesDependency.
  #
  # See: https://github.com/github/codespaces/issues/2080
  def tag_automated_testing
    is_test_user = GitHub.flipper[:codespaces_automated_testing].enabled?(current_user)
    request.env[GitHub::TaggingHelper::CODESPACES_AUTOMATED_TESTING] = is_test_user
  end
end
