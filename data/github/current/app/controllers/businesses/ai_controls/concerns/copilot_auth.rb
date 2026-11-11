# typed: strict
# frozen_string_literal: true

module Businesses
  module AiControls
    module Concerns
      # Shared Copilot authorization helpers for enterprise AI controls controllers.
      module CopilotAuth
        extend ActiveSupport::Concern
        extend T::Helpers

        include Businesses::Concerns::BusinessAccess

        sig { returns(::Copilot::Business) }
        def copilot_business
          @copilot_business ||= T.let(::Copilot::Business.new(this_business), T.nilable(::Copilot::Business))
          @copilot_business
        end

        sig { void }
        def ensure_copilot_enabled
          render_404 unless copilot_business.copilot_enabled?
        end

        # FGP check for React endpoints
        sig { void }
        def ai_controls_read_access_required
          if helpers.show_ai_controls?(this_business) &&
            FeatureFlag.vexi.enabled?(:enterprise_ai_controls_fine_grained_permissions, this_business, default: false)
            # Use fine-grained AI controls permissions
            render_404 unless this_business&.actor_can_read_enterprise_ai_controls?(current_user)
          else
            # Fall back to business owner requirement
            render_404 unless this_business&.owner?(current_user)
          end
        end

        sig { void }
        def ai_controls_write_access_required
          if helpers.show_ai_controls?(this_business) &&
            FeatureFlag.vexi.enabled?(:enterprise_ai_controls_fine_grained_permissions, this_business, default: false)
            # Use fine-grained AI controls permissions
            render_404 unless this_business&.actor_can_write_enterprise_ai_controls?(current_user)
          else
            # Fall back to business owner requirement
            render_404 unless this_business&.owner?(current_user)
          end
        end
      end
    end
  end
end
