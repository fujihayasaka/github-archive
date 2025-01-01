# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module Stafftools
  module User
    class ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

      include ActionView::Helpers::DateHelper
      include Stafftools::Features
      include Stafftools::Sentry
      include Stafftools::Education
      include Stafftools::StatusChecklist
      include Stafftools::Zendesk
      include ActionView::Helpers::NumberHelper
      include StafftoolsHelper
      include Stafftools::SplunkHelper

      include GitHub::Memoizer

      sig { returns(::User) }
      attr_reader :user

      sig { returns(String) }
      def page_title
        "#{user.login} - Overview"
      end

      sig { returns(T::Boolean) }
      def show_private_contribution_count?
        profile_settings = user.profile_settings
        profile_settings.show_private_contribution_count?
      end

      sig { returns(String) }
      def account_type_title
        user.class.to_s
      end

      sig { returns(T::Boolean) }
      def show_spam?
        GitHub.spamminess_check_enabled?
      end

      sig { returns(T::Boolean) }
      def show_user_notes?
        !!(staff_note_dormancy ||
            dupe_login ||
            dupe_email ||
            no_primary_email ||
            disabled_repos ||
            reserved_login)
      end

      sig { returns(T::Boolean) }
      def show_collab_section?
        return false if user.organization?

        user.member_repositories.exists? || show_recent_comments?
      end

      sig { returns(T::Boolean) }
      def show_recent_comments?
        return false if user.organization?

        user.issue_comments.exists? || user.commit_comments.exists? || user.issues.exists? # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end

      sig { returns(Integer) }
      def member_repository_count
        user.member_repositories.count
      end

      sig { returns(String) }
      def dormant_title
        user.dormant?(strict: !GitHub.enterprise?) ? "Dormant" : "Active"
      end

      sig { returns(String) }
      def coding_agent_enablement_setting
        case user.copilot_swe_agent_access
        when Configurable::CopilotSweAgentAccess::State::ALL_REPOS
          "Coding agent enabled in all repositories"
        when Configurable::CopilotSweAgentAccess::State::SELECTED_REPOS
          repos_count = CopilotSweAgent::RepoEnablement.enabled_repositories_for_owner(user).count
          "Coding agent enabled in #{repos_count} #{"repository".pluralize(repos_count)}"
        when Configurable::CopilotSweAgentAccess::State::DISABLED
          "Coding agent disabled in all repositories"
        end
      end

      sig { params(value: T.anything).returns(T::Hash[Symbol, T.untyped]) }
      def dormant_icon_options(value)
        if user.is_dormant_value(value)
          {
            icon: "x",
            color: :danger,
          }
        else
          {
            icon: "check",
            color: :success,
          }
        end
      end

      sig { returns(String) }
      def dormancy_time_period_in_words
        time_period = time_ago_in_words(GitHub.dormancy_threshold.ago).match(/\d.*/)[0]
        time_period == "1 month" ? "month" : time_period
      end

      sig { returns(T::Boolean) }
      def show_dormant_indicator?
        !user.suspended? && !user.sdn_suspended? && (GitHub.enterprise? || current_user.employee?)
      end

      sig { returns(String) }
      def audit_log_abuse_reports
        if GitHub.driftwood_ade_queries_enabled?
          user.recent_abuse_reports_kql_query
        else
          user.recent_abuse_reports_query
        end
      end

      sig { returns(String) }
      def user_audit_log_query
        if GitHub.driftwood_ade_queries_enabled?
          user.audit_log_kql_query
        else
          user.audit_log_query
        end
      end

      sig { returns(String) }
      def user_mobile_audit_log_query
        if GitHub.driftwood_ade_queries_enabled?
          "#{user_audit_log_query} | where action startswith 'mobile_device_public_key.'"
        else
          "#{user_audit_log_query} action:mobile_device_public_key*"
        end
      end

      sig { returns(String) }
      def user_minimized_comments_audit_log_query
        if GitHub.driftwood_ade_queries_enabled?
          <<~KQL
            webevents
            | where user == "#{user.login}" and action endswith ".minimize_comment"
          KQL
        else
          "action:*.minimize_comment user:#{user.login}"
        end
      end

      sig { returns(String) }
      def org_audit_log_activity_events
        if GitHub.driftwood_ade_queries_enabled?
          "webevents | where actor_id == #{user.id} or org_id == #{user.id} | where action !startswith 'staff.'"
        else
          "(actor_id:#{user.id} OR (org_id:#{user.id} AND _exists_:org)) -action:staff.*"
        end
      end

      sig { returns(String) }
      def user_change_password_audit_log_query
        if GitHub.driftwood_ade_queries_enabled?
          <<~KQL
            webevents
            | where action == "user.change_password"
            | where actor_id == #{user.id}
          KQL
        else
          "action:user.change_password actor_id:#{user.id}"
        end
      end

      sig { returns(String) }
      def user_login_audit_log_query
        if GitHub.driftwood_ade_queries_enabled?
          <<~KQL
            webevents
            | where action == "user.login"
            | where actor_id == #{user.id}
          KQL
        else
          "action:user.login actor_id:#{user.id}"
        end
      end

      sig { returns(String) }
      def organization_invitation_audit_log_query
        if GitHub.driftwood_ade_queries_enabled?
          <<~KQL
            webevents
            | where action == "org.invite_member"
            | where user_id == #{user.id}
          KQL
        else
          "action:org.invite_member user_id:#{user.id}"
        end
      end

      sig { returns(String) }
      def compromised_password_audit_log_query
        if GitHub.driftwood_ade_queries_enabled?
          <<~KQL
            webevents
            | where action == "user.exact_email_and_password_match"
            | where user_id == #{user.id}
          KQL
        else
          "action:user.exact_email_and_password_match user_id:#{user.id}"
        end
      end

      sig { returns(T.nilable(String)) }
      def staff_note_dormancy
        if !GitHub.enterprise? && user.recent_staff_note?
          status_li(:recent_note, "Recent staff note")
        end
      end

      sig { returns(T.nilable(SponsorsListing)) }
      def sponsors_listing
        user.sponsors_listing
      end

      sig { returns(T.nilable(String)) }
      def dupe_login
        if user.has_duplicate_login?
          num = helpers.pluralize(user.duplicate_login_count, "other user")
          status_li(:error, "Has duplicate login",
                    "This user shares a login with #{num}.")
        end
      end

      sig { returns(T.nilable(String)) }
      def dupe_email
        if user.has_duplicate_email?
          num = helpers.pluralize(user.duplicate_email_count, "other e-mail record")
          status_li(:error, "Has duplicate e-mail",
                    "This user shares an e-mail with #{num}.")
        end
      end

      sig { returns(T.nilable(String)) }
      def no_primary_email
        return unless user.user?
        unless user.has_primary_email?
          status_li(:error, "Has no primary email",
                    "This user has not selected a primary email address.")
        end
      end

      sig { returns(T.nilable(String)) }
      def disabled_repos
        repos = user.repositories.where("disabled_at IS NOT NULL")
        unless repos.empty?
          names = repos.map { |repo| repo.name }.join(", ")
          status_li(:error, "Has disabled repositories", "Disabled repositories: #{names}")
        end
      end

      sig { returns(T.nilable(String)) }
      def reserved_login
        status_li(:error, "Has reserved login") if user.login_reserved?
      end

      sig { returns(String) }
      def created_at
        user.created_at.to_s
      end

      sig { returns(String) }
      def developer_program_member
        user.developer_program_member? ? "Yes" : "No"
      end

      sig { returns(T::Boolean) }
      def prerelease_agreement?
        !!prerelease_agreement
      end

      sig { returns(T.nilable(::PrereleaseProgramMember)) }
      def prerelease_agreement
        @prerelease_agreement ||= T.let(user.prerelease_agreement, T.nilable(::PrereleaseProgramMember))
      end

      sig { returns(String) }
      def total_disk_usage
        total = git_disk_bytes +
            avatar_disk_bytes +
            user_asset_disk_bytes
        number_to_human_size(total)
      end

      sig { returns(String) }
      def git_disk_usage
        number_to_human_size(git_disk_bytes)
      end

      sig { returns(String) }
      def avatar_disk_usage
        number_to_human_size(avatar_disk_bytes)
      end

      sig { returns(String) }
      def user_asset_disk_usage
        number_to_human_size(user_asset_disk_bytes)
      end

      sig { returns(Integer) }
      def avatar_disk_bytes
        @avatar_disk_bytes ||= T.let(Avatar.storage_disk_usage(owner_type: "User", owner_id: user.id), T.nilable(Integer))
      end

      sig { returns(Integer) }
      def user_asset_disk_bytes
        @user_asset_disk_bytes ||= T.let(UserAsset.storage_disk_usage(user_id: user.id), T.nilable(Integer))
      end

      sig { returns(Integer) }
      def git_disk_bytes
        # number_to_human_size expects bytes, but disk_usage is reported in
        # kilobytes, so convert it first.
        @git_disk_bytes ||= T.let(user.disk_usage * 1024, T.nilable(Integer))
      end

      sig { returns(T::Boolean) }
      def clear_log_disabled?
        e = GitHub.conduit_client.get_user_events(viewer: current_user, user: user)[:items]
        e.empty?
      end

      sig { returns(String) }
      def business_plus_flag
        if user.organization?
          GitHub::Plan.business_plus.titleized_display_name
        else
          helpers.link_to(
              GitHub::Plan.business_plus.titleized_display_name,
              urls.stafftools_user_organization_memberships_path(user, anchor: "enterprise-memberships"))
        end
      end

      sig { returns(T::Boolean) }
      def show_business_plus_flag?
        !GitHub.single_business_environment? && (user.is_enterprise_managed? || user.business_plus?)
      end

      sig { returns(T::Boolean) }
      def show_owning_business?
        !!(!GitHub.single_business_environment? && user.organization? && user.business)
      end

      sig { returns(T::Array[::BusinessOrganizationInvitation]) }
      memoize def pending_business_invitations
        if user.organization?
          organization.business_invitations.pending.joins(:business).all.to_a
        else
          []
        end
      end

      sig { params(authorized_staffer: T::Boolean).returns(String) }
      def user_sdn_screening_status(authorized_staffer: false)
        "Trade Restrictions: #{user.humanize_trade_screening_status(authorized_staffer: authorized_staffer)}"
      end

      sig { returns(String) }
      def ssh_keys
        valid_keys = user.public_keys.to_a.count { |k| k.can_verify_account_ownership? }
        if valid_keys > 0
          icon = helpers.octicon("check", class: "success")
          msg = "#{helpers.pluralize(valid_keys, 'SSH key')}"
        else
          icon = helpers.octicon("x", class: "alert")
          msg = "None of #{helpers.pluralize(user.public_keys.count, 'SSH key')}"
        end
        ssh_keys_link = helpers.link_to(msg, urls.stafftools_user_ssh_keys_path(user))
        helpers.safe_join([icon, ssh_keys_link, "can be used for account recovery."], " ")
      end

      sig { returns(String) }
      def oauth_pats
        limit = 200
        valid_tokens = user.personal_tokens_for_account_recovery(Time.current, limit: limit).count
        if valid_tokens > 0
          icon = helpers.octicon("check", class: "success")
          if valid_tokens == limit
            msg = "#{helpers.pluralize(valid_tokens, 'or more PAT')}"
          else
            msg = "#{helpers.pluralize(valid_tokens, 'PAT')}"
          end
        else
          icon = helpers.octicon("x", class: "alert")
          count = OauthAccessTokens.domain.personal_tokens_count(user.id)
          msg = "None of #{helpers.pluralize(count, 'PAT')}"
        end
        user_pat_link = helpers.link_to(msg, urls.stafftools_user_oauth_tokens_path(user))
        helpers.safe_join([icon, user_pat_link, "can be used for account recovery."], " ")
      end

      sig { returns(T::Boolean) }
      def is_recovery_request_enabled?
        !GitHub.enterprise?
      end

      sig { returns(T.nilable(String)) }
      def staff_recovery_review_text
        current_2fa_recovery_request = self.current_2fa_recovery_request
        return unless current_2fa_recovery_request.present?

        return "Account recovery request declined" if current_2fa_recovery_request.declined_at.present?
        return "Account recovery request approved" if current_2fa_recovery_request.approved_at.present?

        "Account recovery request pending"
      end

      sig { returns(T::Boolean) }
      def current_recovery_request?
        current_2fa_recovery_request.present?
      end

      sig { returns(T.nilable(TwoFactorRecoveryRequest)) }
      def current_2fa_recovery_request
        return unless is_recovery_request_enabled?

        @current_2fa_recovery_request ||= T.let(TwoFactorRecoveryRequest.find_for_staff_review(user), T.nilable(TwoFactorRecoveryRequest))
      end

      sig { returns(String) }
      def sentry_link
        sentry_query_link(
          [Stafftools::Sentry::DOTCOM_PROJECT_ID],
          "user.username:#{user.name}"
        )
      end

      sig { returns(T.nilable(String)) }
      def splunk_link
        splunk_search_url("index=* gh.actor.id=#{user.id}")
      end

      sig { returns(T.nilable(String)) }
      def splunk_sms_link
        splunk_search_url("(index=catchall OR index=sms-deliverability-webhooks) sourcetype=sms-deliverability-webhooks service.name=sms-deliverability-webhooks gh.enduser.id=#{user.id}")
      end

      sig { returns(String) }
      def zendesk_user_url
        zendesk_search_url(user.name)
      end

      sig { returns(String) }
      def zendesk_email_url
        zendesk_search_url("email:#{user.default_notification_email}")
      end

      sig { returns(String) }
      def education_app_user_url
        education_search_url(user.id)
      end

      sig { returns(String) }
      def company_name
        T.cast(user, ::Organization).company.try(:name) || "None"
      end

      sig { params(timestamp: T.nilable(Time)).returns(T.any(String, Date)) }
      def to_date(timestamp)
        if timestamp.blank?
          "None"
        else
          timestamp.to_date
        end
      end

      sig { returns(T.nilable(String)) }
      def default_repository_permission
        return unless user.organization?
        case organization.default_repository_permission
        when :admin
          "Admin — Members of this organization can clone, pull, push, and add new collaborators to all repositories."
        when :write
          "Write — Members of this organization can clone, pull, and push all repositories."
        when :read
          "Read — Members of this organization can clone and pull all repositories."
        else
          "None — Members can only clone and pull public repositories."
        end
      end

      # Public: Should we show the button to force the corporate ToS upgrade prompt?
      sig { returns(T::Boolean) }
      def show_corporate_tos_prompt_toggle?
        return false if GitHub.enterprise?
        return false unless user.organization?

        terms_of_service = organization.terms_of_service
        !terms_of_service.business_terms_of_service? && !terms_of_service.esa_education?
      end

      # Public: Should we show the button to force the ESA+Education ToS upgrade prompt?
      sig { returns(T::Boolean) }
      def show_esa_education_tos_prompt_toggle?
        return false if GitHub.enterprise?
        return false unless user.organization?

        !organization.terms_of_service.esa_education?
      end

      sig { returns(T::Boolean) }
      def enterprise_managed_user_enabled?
        (user.user? && user.is_enterprise_managed?) ||
          (user.organization? && organization.enterprise_managed_user_enabled?)
      end

      sig { returns(::Copilot::User) }
      def copilot_user
        ::Copilot::User.new(user)
      end

      sig { returns(T::Boolean) }
      def copilot_access_allowed?
        copilot_user.copilot_authorizer_object.access_allowed?
      end

      sig { returns(String) }
      def copilot_access_reason
        copilot_user.copilot_authorizer_object.verbose_reason
      end

      sig { returns(T::Boolean) }
      def copilot_allow_public_code_suggestions
        copilot_user.allow_public_code_suggestions?
      end

      sig { returns(T::Boolean) }
      def copilot_public_code_suggestions_configured?
        copilot_user.public_code_suggestions_configured?
      end

      sig { returns(T::Boolean) }
      def copilot_telemetry_enabled
        copilot_user.telemetry_enabled?
      end

      sig { returns(T.nilable(::Copilot::LimitedUser)) }
      def copilot_limited_user
        ::Copilot::LimitedUser.subscribed.find_by(user_id: user.id)
      end

      sig { returns(T::Hash[String, Integer]) }
      def copilot_quotas_remaining
        return {} unless copilot_limited_user.present?
        T.must(copilot_limited_user).quotas_remaining
      end

      sig { returns(T::Boolean) }
      def show_repo_rules?
        user.organization?
      end

      sig { returns(T::Boolean) }
      def show_custom_properties?
        user.organization?
      end

      sig { returns(T.nilable(T::Boolean)) }
      def show_high_profile_signals?
        high_profile, _ = HighProfileSignals.high_profile_user?(user)
        high_profile && current_user.employee? # short circuit on high profile to avoid additional query
      end

      sig { returns(::Organization) }
      memoize def organization
        T.cast(user, ::Organization)
      end
    end
  end
end
