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
      feature_preview_enabled_globally_or_for_current_user?(:diff_ux_refresh)
    end
  end
end
