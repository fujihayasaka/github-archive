# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class AdminView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include Stafftools::LargeFilesView::PreviewTogglerHelper
      include Porter::Urls

      class UnknownConfigurationSettingSource < StandardError
      end

      class ContributionClassHelper
        def initialize(contribution_class, is_flagged)
          @contribution_class = contribution_class
          @is_flagged = is_flagged
        end

        def name
          @contribution_class.name
        end

        def short_name
          @contribution_class.name.demodulize
        end

        def flagged?
          @is_flagged
        end
      end

      attr_reader :user

      def page_title
        "#{user.login} - Admin"
      end

      def audit_query
        "user_id:#{user.id} AND action:org.transform"
      end

      def audit_kql_query
        <<~KQL
          webevents
          | where user_id == #{user.id} and action == 'org.transform'
        KQL
      end

      def show_spam?
        GitHub.spamminess_check_enabled?
      end

      def spammy_rename_delete_overridden?(toggle_type)
        SpammyRenameDeleteOverride.overridden?(user: user, toggle_type: toggle_type)
      end

      def spammy_orgs_rename_delete_overridden?(toggle_type)
        SpammyRenameDeleteOverride.orgs_overridden?(user: user, toggle_type: toggle_type)
      end

      def same_ip_count
        @same_ip_count ||= ::User.by_ip(user.last_ip).count
      end

      def show_role?
        user.user?
      end

      def show_revoke_employee_access?
        employee? if GitHub.require_employee_for_site_admin?
      end

      def show_interaction_ban?
        user.user? && !GitHub.enterprise?
      end

      def account_type
        if site_admin?
          "site admin"
        elsif pending_site_admin?
          "pending site admin (needs 2FA)"
        elsif github_developer?
          "GitHub developer"
        elsif biztools_user?
          "GitHub Biztools user"
        elsif employee?
          "GitHub employee"
        else
          "normal user"
        end
      end

      def site_admin?
        user.site_admin?
      end

      def employee?
        user.employee?
      end

      def pending_site_admin?
        user.has_staff_role? && !site_admin?
      end

      def github_developer?
        user.github_developer?
      end

      def biztools_user?
        user.biztools_user?
      end

      def normal_user_or_employee?
        !site_admin? && !pending_site_admin? && !github_developer? && !biztools_user?
      end

      def interaction_disallowed?
        !::User::InteractionAbility.interaction_allowed?(user: user)
      end

      def interaction_ban_expiry
        expiry = ::User::InteractionAbility.ban_expiry(user)
        expiry && expiry.in_time_zone.strftime("%m-%d-%Y at %H:%M:%S")
      end

      def interaction_ban_duration
        (Time.parse(DateTime.now.to_s) + ::User::InteractionAbility::TTL - Time.parse(DateTime.now.to_s)).to_i / 3600
      end

      def suspension_status
        user.suspended? ? "suspended" : "active"
      end

      def suspension_action
        user.suspended? ? "Unsuspend" : "Suspend"
      end

      def suspension_action_disabled?
        user.ldap_mapped?
      end

      def plan
        unless GitHub.enterprise?
          user.plan.display_name == "free" ? user.plan.name.humanize : user.plan.display_name.humanize
        end
      end

      def has_subscriptions?
        subscriptions = user.subscription_items.map { |item| item[:quantity] if item[:quantity] > 0 }.compact
        !subscriptions.empty? unless GitHub.enterprise?
      end

      def downgradable?
        !GitHub.enterprise? && !user.delegate_billing_to_business? && (plan != "Free" || has_subscriptions?)
      end

      def downgrade_action
        "Change plan"
      end

      def has_repos?
        user.repositories.size > 0
      end

      # force controls
      def force_rejection_local_policy?
        user.force_push_rejection_local? && user.force_push_rejection_policy?
      end

      def force_detail_text(current_setting = nil)
        current_setting ||= user.force_push_rejection

        case current_setting
        when false
          "Allow"
        when "all"
          "Block"
        when "default"
          "Block on the default branch"
        end
      end

      # force controls
      def setting_source_detail_text(target)
        if target == GitHub
          "the instance level"
        else
          # We have no idea where it's coming from, this should only happen
          # when we change cascading and need to add another case here.
          boom = UnknownConfigurationSettingSource.new("Unexpected source for setting. setting_source_detail_text needs to be updated to support #{target.class}")
          boom.set_backtrace(caller)
          Failbot.report!(boom, target: target, fatal: "NO (just reporting)")

          "a higher level"
        end
      end

      def force_rejection_choices
        choices = [
          ["Allow", ""],
          ["Block", "all"],
          ["Block to the default branch", "default"],
        ]

        if user.force_push_rejection_local? && user.force_push_rejection_default_source
          choices << ["Use default from #{setting_source_detail_text(user.force_push_rejection_default_source)}", "_clear"]
        elsif user.force_push_rejection_local?
          # There's no setting that will cascade, so we'll use git's default
          choices << ["Clear and use git’s default (Allow)", "_clear"]
        end

        choices
      end

      def force_selected?(value)
        current_setting ||= user.force_push_rejection

        if !current_setting && value == ""
          true
        elsif current_setting == value
          true
        else
          false
        end
      end

      def ssh_local_policy?
        user.ssh_local? && user.ssh_policy?
      end

      def ssh_choices
        choices = [
          %w[Enabled true],
          %w[Disabled false],
        ]

        if user.ssh_local? && user.ssh_default_source
          choices << ["Use default from #{setting_source_detail_text(user.ssh_default_source)}", "_clear"]
        elsif user.ssh_local?
          # There's no setting that will cascade, so we'll use git's default
          choices << ["Clear and use default (Enabled)", "_clear"]
        end

        choices
      end

      def tos_reasons
        DsaConstants::TOS_MODERATION_REASON_OPTIONS + [
          ["Account Takeover ^", :ACCOUNT_TAKEOVER],
          ["Hide from Public ^", :HIDE_FROM_PUBLIC],
          ["Other ^", :OTHER]
        ]
      end

      def show_rate_limit_allowlisting?
        GitHub.content_creation_rate_limiting_enabled? && user.user?
      end

      def user_allowlisted?
        user.content_creation_rate_limit_allowlisted?
      end

      def allowlisting_user
        if user_temporarily_allowlisted?
          user.temporary_content_creation_allowlisting_user.login
        else
          user.content_creation_rate_limit_allowlister.login
        end
      end

      def allowlisted_at
        if user_temporarily_allowlisted?
          user.temporary_content_creation_allowlisted_at
        else
          user.content_creation_rate_limit_allowlisted_at
        end
      end

      def user_temporarily_allowlisted?
        user.temporarily_content_creation_allowlisted?
      end

      def allowlist_button_text
        user_allowlisted? ? "De-allowlist" : "Allowlist Permanently"
      end

      def temporary_allowlist_button_text
        user_temporarily_allowlisted? ? "Reset temporary limit to 3 days" : "Allowlist for 3 days"
      end

      def display_temporary_allowlist_button?
        user.user_allowlisting.nil?
      end

      def last_rate_limit_violation
        user.last_content_creation_rate_limit_violation
      end

      def rate_limit_audit_log_link_arguments
        { query: " actor_id:#{user.id} AND action:user.#{GitHub::RateLimitedCreation::AUDIT_LOG_EVENT_KEY}" }
      end

      def git_lfs_configurable
        user
      end

      def porter_admin_url
        porter_admin_user_url(user: user) if GitHub.porter_available?
      end

      def contribution_classes
        flagged_contribution_classes = user.flagged_contribution_classes

        # CreatedIssueComment is included *only* on the homepage.
        # That said, we would like the ability to flag this contribution type
        # on a per-user bases.
        #
        # https://github.com/github/github/pull/86756
        classes = Contribution::Collector::CONTRIBUTION_CLASSES + [Contribution::CreatedIssueComment]
        classes.map do |contribution_class|
          is_flagged = flagged_contribution_classes.include? contribution_class
          ContributionClassHelper.new(contribution_class, is_flagged)
        end
      end

      def legal_hold_action_text
        if user.legal_hold?
          "Clear legal hold"
        else
          "Place legal hold"
        end
      end

      # Is this user the owner of any organizations that would prevent their
      # account from being deleted?
      #
      # For Enterprise, a user can't have any solitarily owned organizations. Force
      # dotcom, the user cannot own any organizations.
      #
      # Returns a Boolean.
      def owned_orgs_preventing_deletion?
        return false unless user.user?
        GitHub.enterprise? ? user.solitarily_owned_organizations.any? : user.owned_organizations.any?
      end

      def deletion_disallowed_orgs_reason
        if GitHub.enterprise? && user.solitarily_owned_organizations.any?
          "This account is currently the only owner in these organizations:"
        else
          "This account is currently an owner in these organizations:"
        end
      end

      def deletion_disallowed_orgs_list
        if GitHub.enterprise?
          user.solitarily_owned_organizations.pluck(:login).to_sentence
        else
          user.owned_organizations.pluck(:login).to_sentence
        end
      end

      def deletion_disallowed_plan_reason
        if has_subscriptions?
          "This user has a #{plan} plan with marketplace integrations that must be removed."
        else
          "This user has subscribed to a #{plan}."
        end
      end

      # Should we display the option to toggle deletion/renaming abilities
      # for spammy organizations owned by this user?
      #
      # Returns a Boolean.
      def show_spammy_org_override?
        user.user? && user.owned_organizations.spammy.exists?
      end

      def trade_controls_restriction_events
        user.trade_controls_restriction.valid_events_with_subsequent_state
      end

      def trade_controls_restriction_type
        @_trade_controls_restriction_type ||= user.trade_controls_restriction.type
      end

      def number_of_images_to_scan
        return 0 unless user.user?
        user.assets.count - user.photo_dna_hits.count
      end

      # Determines if we show the 'Send for batch scan' button.
      # See Schaefer project: https://github.com/github/schaefer
      def batch_scannable?(current_user)
        !GitHub.enterprise? && user.user? && current_user.feature_enabled?(:schaefer_send_for_scanning)
      end

      def user_rename_reasons
        [
          "Dormant",
          "2FA recovery failure",
          "Trademark dispute",
          "Internal username request",
          "ATO remediation",
          "Owner requested",
          "Other"
        ]
      end

      def deletion_disallowed_account_reason
        if user.scim_managed_user?
          return "This account cannot be deleted because SCIM provisioning has been enabled."
        end

        "This account cannot be deleted because it is on a paid plan or a member of a paid organization."
      end

      def rename_disabled_button_label
        return "Rename" if user.is_enterprise_managed?

        "Change name"
      end

      def rename_disallowed_reason
        if user.is_enterprise_managed?
          return "EMU user accounts can not be renamed because they are managed through the IdP."
        end

        "This account cannot be renamed because SCIM provisioning has been enabled."
      end

      def deletable_user?
        if GitHub.enterprise?
          return !user.scim_managed_user?
        end

        !(user.paid_plan? || user.orgs_with_private_plan?) || soft_deleted_org?
      end

      def soft_deleted_org?
        user.organization? && user.soft_deleted?
      end

      def show_emu_deprovisioning_button?
        return false if GitHub.single_business_environment?
        return false unless user.user?

        return false if user.is_first_emu_owner?
        user.is_enterprise_managed?
      end

      def show_suspension_button?
        return false unless user.suspendable?
        return true if user.is_first_emu_owner?
        if user.feature_enabled?(:prevent_api_suspension_of_scim_users) || GitHub.enterprise?
          !user.scim_managed_user?
        else
          !user.is_enterprise_managed?
        end
      end

      def show_high_profile_signals?(current_user)
        high_profile, _ = HighProfileSignals.high_profile_user?(current_user)
        current_user.employee? && high_profile
      end
    end
  end
end
