# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Controllers
    class EnterpriseDismissNoticeController < ApplicationController
      include ApplicationController::VerifiedFetchDependency

      depends_on_clusters ApplicationRecord::Domain::Users,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Collab,
        ApplicationRecord::IamAbilities

      allow_verified_fetch only: [:create]

      before_action :login_required

      CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let(%w[
        InProductTargeting::Controllers::EnterpriseDismissNoticeController#create
      ].freeze, T::Array[String])

      # POST /in-product-messaging/enterprise-dismiss-notice
      # Dismisses a notice and redirects to destination URL based on key lookup
      sig { void }
      def create
        notice = params[:notice]
        group = params[:group].present? ? params[:group].to_sym : nil
        business_id = params[:business_id].present? ? params[:business_id].to_i : nil

        if notice.present?
          # Use connected write role to avoid replication lag
          ActiveRecord::Base.connected_to(role: :writing) do
            nudge_memory = InProductTargeting::NudgeMemory.new(current_user)
            nudge_memory.save_a_copy_of_click_analytics_to_dotcom(id: notice, group: group, enterprise_id: business_id)

            current_user.dismiss_business_notice(
              notice,
              business_id: business_id,
            )
            nudge_memory.save_a_copy_of_dismissal_analytics_to_dotcom(id: notice, group: group, enterprise_id: business_id)
          end
        end

        if request.xhr?
          head :ok
        else
          redirect_back(fallback_location: "/")
        end
      end

      private

      # Since we're only dismissing notices for the current user, return current_user as the target
      sig { returns(T.any(Symbol, User)) }
      def resource_for_conditional_access
        return :no_target_for_conditional_access unless logged_in?
        return :no_target_for_conditional_access if GitHub::DeniedLogins.include? current_user.display_login.downcase
        current_user
      end

      sig { returns(Symbol) }
      def target_for_conditional_access
        :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      end
    end
  end
end
