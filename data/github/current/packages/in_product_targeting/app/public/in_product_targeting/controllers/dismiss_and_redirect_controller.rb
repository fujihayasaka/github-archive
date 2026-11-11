# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Controllers
    class DismissAndRedirectController < ApplicationController
      include InProductTargeting::Controllers::Concerns::UtmParams

      depends_on_clusters ApplicationRecord::Domain::Users,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Collab,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Repositories

      before_action :login_required

      DESTINATION_PATHS = T.let({
        "nudge_organization_win_cb_users_back_credit_offer_to_accept" => "/settings/organizations?cb_200_offer_notice=1",
        "dashboard_notify_users_cb_seat_nudge" => "https://docs.github.com/en/copilot/how-tos/set-up/set-up-for-self#2-install-the-copilot-extension-for-your-ide",
        "ipm_accelerate_dashboard_copilot_cli_enabled_nudge" => "https://github.com/github/copilot-cli?tab=readme-ov-file#-getting-started",
        "accelerate_ipm_automatic_ccr_nudge_on_pull_requests" => "/:organization_login/:repository_name/settings/copilot/code_review"
      }.freeze, T::Hash[String, String])

      # GET /in-product-messaging/dismiss-and-redirect
      # Dismisses a notice and redirects to destination URL based on key lookup
      sig { void }
      def show
        notice = params[:notice]
        destination_key = params[:destination_key]
        group = params[:group].present? ? params[:group].to_sym : nil
        business_id = params[:business_id].presence&.to_i
        organization_id = params[:organization_id].presence&.to_i
        repository_id = params[:repository_id].presence&.to_i
        dismiss_scope = params[:dismiss_scope]

        if notice.present?
          # Use connected write role to avoid replication lag
          ActiveRecord::Base.connected_to(role: :writing) do
            T.must(current_user).track_nudge_click(id: notice, group: group, org_id: organization_id, enterprise_id: business_id)

            if dismiss_scope == "user"
              T.must(current_user).dismiss_notice(notice)
              T.must(current_user).track_nudge_dismissal(id: notice, group: group)
            elsif dismiss_scope == "business" && business_id
              T.must(current_user).dismiss_business_notice(
                notice,
                business_id: business_id,
              )
              T.must(current_user).track_nudge_dismissal(id: notice, group: group, enterprise_id: business_id)
            elsif (dismiss_scope == "org" || dismiss_scope == "organization") && organization_id
              T.must(current_user).dismiss_organization_notice(notice, Struct.new(:id).new(organization_id))
              T.must(current_user).track_nudge_dismissal(id: notice, group: group, org_id: organization_id)
            # Backward compatibility: infer dismiss scope from presence of business_id/organization_id.
            # These branches can be removed once all existing nudges pass an explicit dismiss_scope.
            elsif business_id
              T.must(current_user).dismiss_business_notice(
                notice,
                business_id: business_id,
              )
              T.must(current_user).track_nudge_dismissal(id: notice, group: group, enterprise_id: business_id)
            elsif organization_id
              T.must(current_user).dismiss_organization_notice(notice, Struct.new(:id).new(organization_id))
              T.must(current_user).track_nudge_dismissal(id: notice, group: group, org_id: organization_id)
            else
              T.must(current_user).dismiss_notice(notice)
              T.must(current_user).track_nudge_dismissal(id: notice, group: group)
            end
          end
        end

        # Redirect to github.com if destination key not found in map
        if destination_key.present? && DESTINATION_PATHS.key?(destination_key)
          url = T.must(DESTINATION_PATHS[destination_key])

          if url.include?(":organization_login")
            organization_login = Organization.find_by(id: organization_id)&.display_login
            if organization_login.present?
              url = url.gsub(":organization_login", organization_login)
            else
              url = "https://github.com"
            end
          end

          if url.include?(":repository_name")
            repository_name = Repository.find_by(id: repository_id)&.name
            if repository_name.present?
              url = url.gsub(":repository_name", repository_name)
            else
              url = "https://github.com"
            end
          end

          redirect_to add_utm_params(url)
        else
          redirect_to "https://github.com"
        end
      end

      private

      # Since we're only dismissing notices for the current user, return current_user as the target
      sig { returns(T.any(Symbol, User)) }
      def resource_for_conditional_access
        return :no_target_for_conditional_access unless logged_in?
        return :no_target_for_conditional_access if GitHub::DeniedLogins.include? T.must(current_user).display_login.downcase
        T.must(current_user)
      end

      sig { returns(Symbol) }
      def target_for_conditional_access
        :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      end
    end
  end
end
