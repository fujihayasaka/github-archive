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
        "ipm_accelerate_dashboard_copilot_cli_enabled_nudge" => "https://github.com/github/copilot-cli?tab=readme-ov-file#-getting-started",
        "accelerate_ipm_automatic_ccr_nudge_on_pull_requests" => "/:organization_login/:repository_name/settings/copilot/code_review",
        "accelerate_ipm_copilot_business_onboarding_modal_copilot" => "/copilot",
        "accelerate_ipm_copilot_business_onboarding_modal_agents" => "/copilot/agents",
        "accelerate_ipm_copilot_cli_dashboard_for_devs" => "https://docs.github.com/en/copilot/how-tos/copilot-cli/cli-getting-started",
        "general_ipm_roadmap_webinar_2026_q2_nudge_amer_emea" => "https://github.registration.goldcast.io/webinar/1dd0b7b0-5d4e-4c83-b231-24a4eef1675a?utm_source=github&utm_medium=in_product_message&utm_campaign=AMER+Q2+Webinar",
        "general_ipm_roadmap_webinar_2026_q2_nudge_apac" => "https://github.registration.goldcast.io/webinar/8c7527d8-3f54-4934-8fd8-184c6d99b948?utm_source=github&utm_medium=in_product_message&utm_campaign=APAC+Q2+Webinar"
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
        organization_login_param = params[:organization_login].presence
        repository_name_param = params[:repository_name].presence
        business_slug_param = params[:business_slug].presence

        if notice.present?
          # Use connected write role to avoid replication lag
          ActiveRecord::Base.connected_to(role: :writing) do
            nudge_memory = InProductTargeting::NudgeMemory.new(T.must(current_user))
            nudge_memory.save_a_copy_of_click_analytics_to_dotcom(id: notice, group: group, org_id: organization_id, enterprise_id: business_id)

            if dismiss_scope == "user"
              T.must(current_user).dismiss_notice(notice)
              nudge_memory.save_a_copy_of_dismissal_analytics_to_dotcom(id: notice, group: group)
            elsif dismiss_scope == "business" && business_id
              T.must(current_user).dismiss_business_notice(
                notice,
                business_id: business_id,
              )
              nudge_memory.save_a_copy_of_dismissal_analytics_to_dotcom(id: notice, group: group, enterprise_id: business_id)
            elsif (dismiss_scope == "org" || dismiss_scope == "organization") && organization_id
              T.must(current_user).dismiss_organization_notice(notice, Struct.new(:id).new(organization_id))
              nudge_memory.save_a_copy_of_dismissal_analytics_to_dotcom(id: notice, group: group, org_id: organization_id)
            # Backward compatibility: infer dismiss scope from presence of business_id/organization_id.
            # These branches can be removed once all existing nudges pass an explicit dismiss_scope.
            elsif business_id
              T.must(current_user).dismiss_business_notice(
                notice,
                business_id: business_id,
              )
              nudge_memory.save_a_copy_of_dismissal_analytics_to_dotcom(id: notice, group: group, enterprise_id: business_id)
            elsif organization_id
              T.must(current_user).dismiss_organization_notice(notice, Struct.new(:id).new(organization_id))
              nudge_memory.save_a_copy_of_dismissal_analytics_to_dotcom(id: notice, group: group, org_id: organization_id)
            else
              T.must(current_user).dismiss_notice(notice)
              nudge_memory.save_a_copy_of_dismissal_analytics_to_dotcom(id: notice, group: group)
            end
          end
        end

        # Redirect to github.com if destination key not found in map
        if destination_key.present? && DESTINATION_PATHS.key?(destination_key)
          url = T.must(DESTINATION_PATHS[destination_key])

          if url.include?(":business_slug")
            business_slug =
              if valid_business_slug_param?(business_slug_param)
                business_slug_param
              else
                slug = Business.find_by(id: business_id)&.slug
                if slug.nil?
                  slug = Organization.find_by(id: organization_id)&.business&.slug
                end
                slug
              end

            if business_slug.present?
              url = url.gsub(":business_slug", business_slug)
            else
              url = "https://github.com"
            end
          end

          if url.include?(":organization_login")
            organization_login =
              if valid_organization_login_param?(organization_login_param)
                organization_login_param
              else
                Organization.find_by(id: organization_id)&.display_login
              end

            if organization_login.present?
              url = url.gsub(":organization_login", organization_login)
            else
              url = "https://github.com"
            end
          end

          if url.include?(":repository_name")
            repository_name =
              if valid_repository_name_param?(repository_name_param)
                repository_name_param
              else
                Repository.find_by(id: repository_id)&.name
              end

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

      sig { params(value: T.nilable(String)).returns(T::Boolean) }
      def valid_organization_login_param?(value)
        return false if value.blank?
        value.length <= User::LOGIN_MAX_LENGTH && User::LOGIN_REGEX.match?(value)
      end

      sig { params(value: T.nilable(String)).returns(T::Boolean) }
      def valid_business_slug_param?(value)
        return false if value.blank?
        value.length <= Business::MAX_SLUG_LENGTH && Business::SLUG_REGEX.match?(value)
      end

      VALID_REPOSITORY_NAME_REGEX = T.let(/\A[\w.\-]+\z/, Regexp)

      sig { params(value: T.nilable(String)).returns(T::Boolean) }
      def valid_repository_name_param?(value)
        return false if value.blank?
        return false unless value.length.between?(1, Repository::NAME_MAX_LENGTH)
        return false if %w[. .. ...].include?(value)
        VALID_REPOSITORY_NAME_REGEX.match?(value)
      end
    end
  end
end
