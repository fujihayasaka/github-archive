# typed: true
# frozen_string_literal: true

module Stafftools
  module AdvancedSecurity
    class MeteredServicesLocksController < StafftoolsController
      before_action :ensure_entity_exists

      def create
        if params[:is_bundled] == "true"
          entity.lock_advanced_security_metered_usage("locked via stafftools", actor: current_user)
          flash[:notice] = "Metered Advanced Security services locked"
        else
          entity.lock_code_security_metered_usage("locked via stafftools", actor: current_user)
          entity.lock_secret_protection_metered_usage("locked via stafftools", actor: current_user)
          flash[:notice] = "Metered Code Security & Secret Protection services locked"
        end

        redirect_back(fallback_location: "/")
      end

      def destroy
        if params[:is_bundled] == "true"
          entity.unlock_advanced_security_metered_usage(actor: current_user)
          flash[:notice] = "Metered Advanced Security services unlocked"
        else
          entity.unlock_code_security_metered_usage(actor: current_user)
          entity.unlock_secret_protection_metered_usage(actor: current_user)
          flash[:notice] = "Metered Code Security & Secret Protection services unlocked"
        end

        redirect_back(fallback_location: "/")
      end

      private

      def entity
        @entity
      end

      def ensure_entity_exists
        @entity =
          case params[:entity_type]
          when "Business"
            ::Business.find(params[:entity_id])
          when "Organization"
            ::User.find(params[:entity_id])
          end

        render_404 if entity.nil?
      end
    end
  end
end
