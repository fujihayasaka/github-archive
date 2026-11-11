# typed: true
# frozen_string_literal: true

module Orgs
  module Invitations
    class ReinstateView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include EnterpriseManagedUsersHelper

      attr_reader :restorable_organization_user, :existing_invitation
      attr_writer :existing_invitation
      delegate :user, :organization, to: :restorable_organization_user

      # Pseudo-factory method returning the class name constant of the
      # appropriate ReinstateView subclass. Returns the constant rather than an
      # instance because #create_view_model expects the former.
      #
      # OrganizationInvitation -> Class
      # is_enterprise_managed  -> is the caller enterprise managed. We can't use
      #                           the instance method enterprise_managed_user_enabled?
      #                           because the ViewModel has not yet been created
      def self.select_view(invitation = nil, is_enterprise_managed = false)
        if GitHub.bypass_org_invites_enabled? || is_enterprise_managed
          # Used on GHES and GHEC EMUs, where users are added to orgs directly,
          # without needing to accept an invitation
          return CreateMembershipImmediatelyView
        end

        case invitation
        when :blank?.to_proc
          CreateInvitationView
        when :reinstate?.to_proc
          UpdateReinstateInvitationView
        else
          UpdateStartFreshInvitationView
        end
      end

      # Public: The name of the organization issuing the invitation.
      #
      # Returns a String
      def organization_name
        organization.try(:safe_profile_name)
      end

      # Public: Was the user a direct member of the org? If not they must be an
      # outside collaborator.
      #
      # Returns true or false.
      def organization_direct_member?
        restorable_organization_membership.present?
      end

      # Public: What was the users role in the organization? Should only be used if
      # they were a direct member.
      #
      # Returns a String.
      def organization_role
        if restorable_organization_membership.admin?
          "Owner"
        else
          "Member"
        end
      end

      def invitee_login
        "@#{user.display_login}"
      end

      # Public: Returns the teams that they belonged to that still exist.
      #
      # Returns an array of teams.
      def teams
        team_ids = restorable_team_memberships.pluck(:subject_id)
        scope = Team.where(id: team_ids)
        scope = scope.not_externally_managed if enterprise_managed_user_enabled?
        RestorableTypeView.new(
          scope: scope,
          model_id: "team",
          singular: "team",
          plural: "teams",
          phrase: "was a member of",
          octicon: "people",
        )
      end

      # Public: The repositories they were collaborators on that still exist. These
      # should only exist if they were an outside collaborator in the organization.
      #
      # Returns an array of repositories.
      def repositories
        repository_ids = restorable_repository_memberships.pluck(:subject_id)
        scope = Repository.where(id: repository_ids)
        RestorableTypeView.new(
          scope: scope,
          model_id: "repository",
          singular: "repository privilege",
          plural: "repository privileges",
          phrase: "had",
          octicon: "repo",
        )
      end

      # Public: The forks that were archived and can still be restored.
      #
      # Returns an array of archived repositories.
      def forks
        archived_repository_ids = restorable_forks.pluck(:archived_repository_id)
        scope = ::Repository.deleted.where(id: archived_repository_ids)
        RestorableTypeView.new(
          scope: scope,
          model_id: "fork",
          singular: "fork",
          plural: "forks",
          phrase: "had",
          octicon: "repo-forked",
        )
      end

      # Public: The repositories they were watching that still exist.
      #
      # Returns an array of repositories.
      def watching
        repository_ids = restorable_watched_repositories.pluck(:repository_id)
        scope = Repository.where(id: repository_ids)
        RestorableTypeView.new(
          scope: scope,
          model_id: "watching",
          singular: "repository",
          plural: "repositories",
          phrase: "was watching",
          octicon: "eye",
        )
      end

      # Public: The repositories they starred in the organization that still exist.
      #
      # Returns an array of repositories.
      def stars
        repository_ids = restorable_repository_stars.pluck(:repository_id)
        scope = Repository.where(id: repository_ids)
        RestorableTypeView.new(
          scope: scope,
          model_id: "star",
          singular: "star",
          plural: "stars",
          phrase: "had",
          octicon: "star",
        )
      end

      # Public: The issues they were assigned to that still exist.
      #
      # Returns an array of issues.
      def issue_assignments
        issue_ids = restorable_issue_assignments.pluck(:issue_id)
        scope = Issue.where(id: issue_ids)
        RestorableTypeView.new(
          scope: scope,
          model_id: "issue_assignment",
          singular: "issue assignment",
          plural: "issue assignments",
          phrase: "had",
          octicon: "issue-opened",
          label_attribute: :title,
        )
      end

      def enterprise_managed_user_enabled?
        organization.enterprise_managed_user_enabled?
      end

      private

      delegate :issue_assignments,
        :repository_stars,
        :watched_repositories,
        :repositories,
        :memberships,
        to: :restorable,
        prefix: true

      alias_method :restorable_forks, :restorable_repositories

      # Internal: The parent Restorable for the restorable organization user.
      #
      # Returns a Restorable.
      def restorable
        @restorable ||= restorable_organization_user.restorable
      end

      # Internal: The restorable organization membership.
      #
      # Returns a Restorable::Membership or nil.
      def restorable_organization_membership
        restorable_memberships.organization_memberships.first
      end

      # Internal: The restorable team memberships.
      #
      # Returns an ActiveRecord::Relation.
      def restorable_team_memberships
        restorable_memberships.team_memberships
      end

      # Internal: The restorable repository memberships.
      #
      # Returns an ActiveRecord::Relation.
      def restorable_repository_memberships
        restorable_memberships.repository_memberships
      end
    end
  end
end
