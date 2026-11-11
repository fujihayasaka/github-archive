# typed: true
# frozen_string_literal: true

module ApplicationController::SyntheticTestDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))
    helper_method :synthetic_test?
  end

  def synthetic_test?
    request.headers["X-GITHUB-SYNTHETIC-TEST"].present?
  end
end
