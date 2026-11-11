# typed: strict
# frozen_string_literal: true

# Shared functionality for saving and loading Dependabot alerts filter views across different scopes
# (repository, organization, and business/enterprise levels).
#
# Controllers including this concern should implement:
# - `scope_context` method that returns a hash with the appropriate context for logging
#   (e.g., { repository_id: @repo.id } or { organization_id: @org.id })
module DependabotAlertsSavedView
  extend ActiveSupport::Concern
  extend T::Helpers

  # Methods that must be implemented by the including controller
  requires_ancestor { ApplicationController }

  included do
    # Common save_view action across all Dependabot alerts controllers
    sig { void }
    def save_view # rubocop:todo GitHub/UseRestfulActions
      return head :not_found unless current_user

      query_string = params[:query].to_s.strip

      if query_string.blank?
        return render json: { error: "Query cannot be blank" }, status: :unprocessable_entity
      end

      save_current_view_for_user(query_string)

      render json: { success: true }
    rescue => e
      GitHub.logger.warn("Failed to save Dependabot alerts view",
        { user_id: current_user&.id, error: e.message }.merge(scope_context)
      )
      render json: { error: "Failed to save view" }, status: :internal_server_error
    end

    private

    sig { params(query_string: String).void }
    def save_current_view_for_user(query_string)
      return unless current_user

      ActiveRecord::Base.connected_to(role: :writing) do
        saved_view = VulnerabilityAlertSavedView.find_or_initialize_by(
          user_id: current_user.id,
          dashboard_type: :dependabot
        )

        saved_view.query = query_string
        saved_view.name = "Dependabot Alerts" if saved_view.name.blank?
        saved_view.save!

        GitHub.logger.info("Dependabot alerts view saved",
          T.unsafe({ user_id: current_user.id, query: query_string }.merge(scope_context))
        )
      end
    end

    sig { returns(T.nilable(String)) }
    def load_saved_view_for_user
      return nil unless current_user

      saved_view = VulnerabilityAlertSavedView.find_by(
        user_id: current_user.id,
        dashboard_type: :dependabot
      )

      if saved_view
        GitHub.logger.info("Dependabot alerts view loaded",
          T.unsafe({ user_id: current_user.id, query: saved_view.query }.merge(scope_context))
        )
        saved_view.query
      else
        nil
      end
    rescue => e
      GitHub.logger.warn("Failed to load Dependabot alerts view",
        T.unsafe({ user_id: current_user&.id, error: e.message }.merge(scope_context))
      )
      nil
    end

    # Abstract method to be implemented by including controllers
    # Returns a hash with the appropriate scope context for logging
    # e.g., { repository_id: 123 }, { organization_id: 456 }, or { business_id: 789 }
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def scope_context
      raise NotImplementedError, "Including controller must implement #scope_context"
    end
  end
end
