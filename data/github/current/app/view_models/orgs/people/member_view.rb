# typed: true
# frozen_string_literal: true

module Orgs
  module People
    class MemberView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include Orgs::People::RoleDescriptionMethods
      include Orgs::People::RoleNameMethods
      include ::TwoFactorRequirementHelper

      attr_reader :member
      attr_reader :organization
      attr_reader :eligible_domain_emails

      def team_count
        organization.teams_for(member, viewer: current_user).size
      end

      def organization_roles_count
        team_ids = organization.teams_for(member, viewer: current_user).pluck(:id)
        role_filter = OrganizationRole.visible_roles(organization)
        user_roles = UserRole.joins(:role).where(
          target_type: "Organization", target_id: organization.id,
          actor_type: "User", actor_id: member.id,
          role: role_filter
        ).count
        team_roles = UserRole.joins(:role).where(
          target_type: "Organization", target_id: organization.id,
          actor_type: "Team", actor_id: team_ids,
          role: role_filter
        ).count

        user_roles + team_roles
      end

      # Public: checks is the member has been suspended by an Identity Provider
      #
      # Returns Boolean
      def suspended?
        return false if member.nil?
        return false unless enterprise_managed?

        return true if member.external_identities.empty?
        member.external_identities.first&.disabled_at?
      end

      def direct_or_team_member?
        return @direct_or_team_member if defined?(@direct_or_team_member)
        @direct_or_team_member = organization.direct_or_team_member?(current_user)
      end

      # Public: Is this member's org membership publicized?
      #
      # Returns a boolean.
      def public_member?
        organization.public_member?(member)
      end

      # Public: Should admin controls and info be shown in this view?
      #
      # Returns a boolean.
      def show_admin_stuff?
        organization.adminable_by?(current_user)
      end

      # Public: Should display custom organization role counts?
      #
      # Returns a boolean.
      def show_org_role_assignment_counts?
        organization.adminable_by?(current_user)
      end

      # Public: The URL representing this organization member.
      #
      # Returns a string path
      def member_url
        if show_admin_stuff?
          urls.org_person_path(organization, member)
        else
          urls.user_path(member)
        end
      end

      # Public: Should we show a warning about 2FA being disabled
      #
      # Returns a boolean.
      def member_two_factor_enabled?
        two_factor_enabled?(member)
      end

      # Public: Whether or not the user is subject to an active account 2FA requirement.
      #
      # Returns a boolean.
      def member_has_active_account_two_factor_requirement?
        active_account_two_factor_requirement?(member)
      end

      # Public: Whether or not the user is subject to a pending account 2FA requirement.
      #
      # Returns a boolean.
      def member_has_pending_account_two_factor_requirement?
        pending_account_two_factor_requirement?(member)
      end

      # Public: The date on which account-base 2FA is required.
      #
      # Returns a Time in UTC.
      def member_account_two_factor_required_by_date
        account_two_factor_required_by_date(member)
      end

      # Public: Is the organization enterprise managed
      #
      # Returns a boolean
      def enterprise_managed?
        organization.scim_managed_enterprise?
      end

      # Public: Should we show 2fa information
      #
      # Returns a boolean.
      def show_2fa?
        return false if enterprise_managed?
        show_admin_stuff? && GitHub.auth.two_factor_authentication_enabled?
      end

      # Public: Should we display the verified domain emails for each user?
      # Note: will display both verified and approved domain emails in GHES/AE, but only
      # the emails from verified domains on GHEC.
      #
      # Returns a Boolean.
      def show_verified_emails?
        show_admin_stuff? && organization.supports_showing_verified_domain_emails?
      end

      # Public: The eligible (verified or approved) domain email for this user to display.
      #
      # Returns: String | nil
      def admin_viewable_domain_email
        admin_viewable_domain_emails.first
      end

      # Public: all the email addresses for this user from eligible (verified or approved)
      # domains. Show a message
      # "Has approved domain email" if user doesn't have any verified domain emails, but
      # has one or more approved domain emails. We want to allow admin to see that this
      # user will receive notifications, without showing them an email address from an
      # approved domain.
      #
      # Returns: Array[String]
      def admin_viewable_domain_emails
        return @domain_emails if defined?(@domain_emails)

        @domain_emails = eligible_domain_emails.select do |user_email|
          organization.show_user_email_address?(user_email)
        end
        # assume that any emails that were removed were from approved domain addresses.
        # The "Has approved domain email" message will be appended if eligible_domain_emails
        # somehow returns an email that's neither verified, nor approved, but ... it's not
        # supposed to do that.
        if @domain_emails.length < eligible_domain_emails.length
          @domain_emails << "Has approved domain email"
        end

        @domain_emails
      end

      # Public: Should we show the link to view more verified/approved domain emails
      #         for this user?
      #
      # Returns a Boolean.
      def show_more_emails_link?
        admin_viewable_domain_emails.length > 1
      end

      # Public: Can this user publicize or conceal their membership in this org?
      def can_change_visibility?
        if organization.public_member?(member)
          organization.can_conceal_memberships?(current_user, members: [member])
        else
          organization.can_publicize_memberships?(current_user, members: [member])
        end
      end

      def enterprise_licenses
        @enterprise_licenses ||= Businesses::EnterpriseLicensesView.for_business(organization.business)
      end

      def volume_licenses
        @volume_licenses ||= Businesses::VolumeLicensesView.for_business(organization.business)
      end

      # Public: What's this member's role?
      #
      # Returns an Organization::Role.
      def role
        @role ||= Organization::Role.new(organization, member)
      end

      # Public: The text to display when no admin viewable domain email to display
      #
      # Returns a String.
      def no_admin_viewable_domain_email
        return "No verified or approved domain email" if VerifiableDomain.approved_domain_emails_visible_to_admins?
        "No verified domain email"
      end
    end
  end
end
