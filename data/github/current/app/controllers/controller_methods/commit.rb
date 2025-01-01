# typed: true
# frozen_string_literal: true

module ControllerMethods
  module Commit
    extend ActiveSupport::Concern
    extend T::Helpers

    requires_ancestor { ApplicationController }

    included do
      T.bind(self, T.class_of(ApplicationController))
    end

    private

    def react_commit_enabled?
      return GitHub.react_commit_view_enabled? if GitHub.enterprise?
      FeatureFlag.vexi.enabled?(:diff_ux_refresh, default: true)
    end
  end
end
