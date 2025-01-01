# typed: true
# frozen_string_literal: true

module Api::App::CodespacesDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Api::App }

  included do
    T.bind(self, T.class_of(Api::App))
    # Tag requests involving automated test users so that they can be excluded
    # from metrics. Counterpart to ApplicationController::CodesCodespaceTagActionDependency.
    #
    # See: https://github.com/github/codespaces/issues/2080
    before do
      is_test_user = FeatureFlag.vexi.enabled?(:codespaces_automated_testing, current_user, default: false)
      request.env[GitHub::TaggingHelper::CODESPACES_AUTOMATED_TESTING] = is_test_user
    end
  end
end
