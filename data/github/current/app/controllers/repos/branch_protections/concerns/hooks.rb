# typed: strict
# frozen_string_literal: true

module Repos
  module BranchProtections
    module Concerns
      module Hooks
        extend ActiveSupport::Concern
        extend T::Helpers

        requires_ancestor { ApplicationController }

        private

        sig { void }
        def ensure_plan_supports_rules
          render_404 unless current_repository.plan_supports?(:protected_branches)
        end

        sig { void }
        def ensure_read_only_enabled
          render_404 unless FeatureFlag.vexi.enabled?("branch_protections_read_only", default: false)
        end
      end
    end
  end
end
