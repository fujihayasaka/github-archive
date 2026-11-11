# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Controllers
    class DismissalController < ApplicationController
      include ApplicationController::VerifiedFetchDependency

      depends_on_clusters ApplicationRecord::Domain::Users,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Collab,
        ApplicationRecord::IamAbilities

      before_action :login_required
      allow_verified_fetch only: [:create]

      CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let(%w[
        InProductTargeting::Controllers::DismissalController#create
      ].freeze, T::Array[String])

      # POST /track-nudge-dismissal
      sig { void }
      def create
        id = params[:id]
        return render json: { success: false }, status: :bad_request unless id.present?

        group = params[:group]&.to_sym
        enterprise_id = params[:enterprise_id].present? ? params[:enterprise_id] : nil
        org_id = params[:org_id].present? ? params[:org_id] : nil

        ActiveRecord::Base.connected_to(role: :writing) do
          InProductTargeting::NudgeMemory.new(current_user).save_a_copy_of_dismissal_analytics_to_dotcom(id: id, group: group, org_id: org_id, enterprise_id: enterprise_id)
          current_user.dismiss_notice(id) if UserNotice.find(id)
        end

        render json: { success: true }
      end

      private

      # Safe because :login_required
      sig { returns(T.any(Symbol, User)) }
      def resource_for_conditional_access
        # Ensure we have a resource that supports conditional access
        return :no_resource_for_conditional_access unless current_user  # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
        current_user
      end

      # Safe because :login_required
      sig { returns(T.any(Symbol, User)) }
      def target_for_conditional_access
        # Target should always be the current user for in-product messaging
        current_user || :no_target_for_conditional_access  # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      end
    end
  end
end
