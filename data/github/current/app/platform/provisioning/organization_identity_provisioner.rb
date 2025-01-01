# typed: false
# frozen_string_literal: true
# rubocop:disable GitHub/UsePlatformErrors

module Platform
  module Provisioning
    # Used for Orgs provisioning: only sets the user on the given Organization
    class OrganizationIdentityProvisioner

      INVITATION_ACCEPTANCE_ERRORS = [:user_already_linked, :email_not_associated_with_logged_in_user]

      # Public: Finds an existing identity under the organization, based on the data
      #         provided by the IdP.
      #
      # organization_id - The ID of the Organization the identity is under.
      # user_data       - The Platform::Provisioning::UserData with all of the
      #                   IdP provided data about the user.
      # mapper          - The provisioning mapper responsible for mapping the
      #                   provided user_data to an external identity. This is
      #                   specific for the provisioning scheme (e.g. SAML vs SCIM).
      def self.find(organization_id:, user_data:, mapper: Platform::Provisioning::SamlMapper)
        return internal_provisioning_error_status unless organization = Organization.find_by_id(organization_id)

        identity = mapper.find_identity \
          target: organization,
          user_data: user_data

        success_status(identity)
      end

      # Public: Updates or provisions an identity under the organization.
      #
      # organization_id - The ID of the Organization the identity is under.
      # identity_guid   - (Optional) The GUID of the external identity to
      #                   provision. If not specified, the mapper will be used
      #                   to find or build one.
      # user_data       - The Platform::Provisioning::UserData with all of the
      #                   IdP provided data about the user.
      # mapper          - The provisioning mapper responsible for mapping the
      #                   provided user_data to an external identity. This is
      #                   specific for the provisioning scheme (e.g. SAML vs SCIM).
      # inviter_id      - (Optional) The ID of the user sending the invitation. Useful when
      #                   updating a pending invitation
      def self.provision(organization_id:, identity_guid: nil, user_data:, mapper:, inviter_id: nil)
        return internal_provisioning_error_status unless organization = Organization.find_by_id(organization_id)
        return identity_not_found_error_status unless identity_guid.nil? || identity = organization.saml_provider.external_identities.where(guid: identity_guid).first

        invitation = identity.try(:organization_invitation)

        provision_identity(organization: organization, identity: identity, user_data: user_data, mapper: mapper) do |identity|
          next success_status(identity) unless has_pending_invite_with_different_email?(identity, invitation)
          next internal_provisioning_error_status unless inviter = User.find_by_id(inviter_id)

          invitation.cancel(actor: inviter)

          # clean up the cancelled invitation's associations
          invitation.update!(external_identity: nil)
          identity.reload

          invite_identity(organization, identity, inviter)
        end
      end

      def self.validate_identity_relink(target:, user_id:, user_data:, mapper:)
        return internal_provisioning_error_status unless organization = Organization.find_by_id(target.id)
        return internal_provisioning_error_status unless user = User.find_by_id(user_id)

        mapper.validate_identity_relink \
          target: organization,
          user: user,
          user_data: user_data
      end

      # Public: Provisions a new identity under the organization for the given
      # user.
      #
      # organization_id - The ID of the Organization the identity is under.
      # user_id         - The ID of the User the identity is linked to.
      # user_data       - The Platform::Provisioning::UserData with all of the
      #                   IdP provided data about the user.
      # mapper          - The provisioning mapper responsible for mapping the
      #                   provided user_data to an external identity. This is
      #                   specific for the provisioning scheme (e.g. SAML vs SCIM).
      # sso_invitation_token - The ID of the Organization::Invitation being accepted
      #                   on behalf of the user.
      def self.provision_and_add_member(organization_id:, user_id:, user_data:, mapper:, sso_invitation_token: nil)
        return internal_provisioning_error_status unless organization = Organization.find_by_id(organization_id)
        return internal_provisioning_error_status unless user = User.find_by_id(user_id)

        provision_identity(organization: organization, user: user, user_data: user_data, mapper: mapper) do |identity|
          create_membership(identity, sso_invitation_token: sso_invitation_token)
        end
      end

      # Public: Provisions a new identity under the organization, inviting the identity
      # via the given email address (when present).
      #
      # If the identity is already linked to a user, no invitation is delivered.
      #
      # organization_id - The ID of the Organization the identity is under.
      # inviter_id      - The ID of the actor sending the invitation.
      # inviter_type    - The type of the actor sending the invitation (defaults to User).
      # user_data       - The Platform::Provisioning::UserData with all of the
      #                   IdP provided data about the user.
      # mapper          - The provisioning mapper responsible for mapping the
      #                   provided user_data to an external identity. This is
      #                   specific for the provisioning scheme (e.g. SAML vs SCIM).
      def self.provision_and_invite(organization_id:, user_data:, inviter_id:, inviter_type: User, mapper:)
        return internal_provisioning_error_status unless organization = Organization.find_by_id(organization_id)

        inviter = case inviter_type.to_s
        when "IntegrationInstallation"
          if (installation = IntegrationInstallation.find_by(id: inviter_id))
            installation.bot
          end
        when "User"
          User.find_by(id: inviter_id)
        end

        return internal_provisioning_error_status if inviter.nil?

        provision_identity(organization: organization, user_data: user_data, mapper: mapper) do |identity|
          next success_status(identity) if identity.user.present?
          next success_status(identity) unless identity.scim_user_data.email.present?
          invite_identity(organization, identity, inviter)
        end
      end

      # Public: De-provisions an identity and removes user from organization.
      #
      # organization_id - The ID of the Organization the identity is under.
      # user_data     - The Platform::Provisioning::UserData with all of the
      #                 IdP provided data about the user. Optional and will be
      #                 blank for DELETE requests.
      # identity_guid - The guid of the external_identity to be deprovisioned
      # actor_id      - Id of the actor making the deprovision request
      # hard_delete   - If the deprovision request is a "hard delete". This means
      #                 the External identity will not be used again.
      def self.deprovision(organization_id:, user_data: nil, identity_guid:, actor_id:, hard_delete: false)
        return internal_provisioning_error_status unless organization = Organization.find_by_id(organization_id)
        return internal_provisioning_error_status unless actor = User.find_by_id(actor_id)

        identity = organization.
          saml_provider.
          external_identities.
          with_attributes.
          where(guid: identity_guid).
          first
        return identity_not_found_error_status unless identity.present?
        return cannot_deprovision_self_error_status if identity.user_id == actor_id

        user = identity.user

        invitations = organization.
          pending_invitations.
          with_invitee_or_normalized_email(invitee: user, emails: identity.scim_user_data.emails)

        credential_authorizations = Organization::CredentialAuthorization.where \
          actor_id: identity.user_id,
          organization_id: organization_id

        context = {
          external_identity: identity,
          operation: "deprovision",
          identity_mapper: Platform::Provisioning::ScimMapper.to_s,
        }

        GitHub.context.push context
        Audit.context.push context

        ExternalIdentity.transaction do
          identity.destroy
          credential_authorizations.destroy_all

          invitations.each { |invitation| invitation.cancel(actor: actor) }

          if user
            organization.remove_member(user, background_team_remove_member: true)
          end
        end

        success_status(identity)
      end

      # Internal: Builds a failed status when we weren't able to find the
      # user and/or organization to provision an identity for.
      #
      # This is not the result of user or IdP error. If this happens,
      # it is a problem on our end.
      def self.internal_provisioning_error_status
        Platform::Provisioning::Result.new \
          errors: Platform::Provisioning::Error.internal_error(
            message: "An internal error has occurred. Please try again. If the problem persists, contact support.",
          )
      end

      # Internal: Builds a failed status when we weren't able to find the identity
      # that the user is trying to operate on
      def self.identity_not_found_error_status
        Platform::Provisioning::Result.new \
          errors: Platform::Provisioning::Error.identity_not_found(
            message: "Unable to find the submitted identity. Please verify the identity information and submit again.",
          )
      end

      # Internal: Builds a failed status when the admin that authenticated is the
      # same as the user that they are attempting to deprovision
      def self.cannot_deprovision_self_error_status
        Platform::Provisioning::Result.new \
          errors: Platform::Provisioning::Error.forbidden_error(
            message: "Unable to deprovision the admin authenticated to perform the SCIM actions. Authenticate your SCIM client with a different account and try again.",
          )
      end

      # Internal: Builds a success status
      def self.success_status(identity)
        Platform::Provisioning::Result.success(external_identity: identity)
      end

      def self.save_identity(identity, organization: nil, user: nil, mapper:)
        if identity.save
          success_status(identity)
        else
          messages = identity.errors.full_messages
          GitHub.logger.error("OrganizationIdentityProvisioner.save_identity has failed", "exception.message" => messages)

          if identity.errors.size == 1 && identity.errors.first.attribute == :base
            Platform::Provisioning::Result.new \
            errors: messages.map { |m| Platform::Provisioning::Error.invalid_identity(message: m) }
          else
            Platform::Provisioning::Result.new \
              errors: messages.map { |m| Platform::Provisioning::Error.bad_request_error(message: m) }
          end
        end
      end

      def self.create_membership(identity, sso_invitation_token: nil, organization: nil)
        organization ||= identity.target

        # Look up pending invitations for this user and/or the external identity
        # (provisioned via SCIM API calls by the identity provider).
        invitations = pending_invitations(external_identity: identity, organization: organization, token: sso_invitation_token)

        # Check if the organization has a seat for the User account.
        has_seat_for = ActiveRecord::Base.connected_to(role: :reading) do
          organization.has_seat_for?(identity.user)
        end

        # Check if the user has a restorable membership.
        restorable = Restorable::OrganizationUser.restorable(organization, identity.user)

        # Log metrics for calls to create membership.
        GitHub.dogstats.increment("organization_identity_provisioner", tags: [
          "op:create_membership",
          "has_seat:#{has_seat_for}",
          "invitations:#{invitations.count}",
          "invite_token:#{sso_invitation_token.present?}",
          "restorable:#{restorable.present?}",
        ])

        # Handle organizations that have reached their seat limit and the
        # user does not have a seat reserved for them via a pending invitation.
        if !has_seat_for && invitations.empty?
          return Platform::Provisioning::Result.target_at_seat_limit_error \
            external_identity: identity
        end

        # Organization memberships are only restored under two conditions:
        #
        # 1. If the user was removed from the organization due to SAML
        #    enforcement and *not* re-invited
        # 2. If the user was removed from the organization and re-invited with
        #    an invitation role of :reinstate
        #
        # This allows admins to re-invite members to SAML-enabled organizations
        # while choosing to "start fresh" in terms of the user's permissions.
        accept_status = invitations.map { |invitation| invitation.accept(acceptor: identity.user) }
        errors = []
        reasons = accept_status.select { |status| status.error? }

        reasons.uniq.each do |reason|
          errors << Platform::Provisioning::Error.add_member(message: "Failed to accept invitation: #{reason.error}", status: reason.status)
        end

        # We're only expecting one type of failure if the feature flag is turned off.
        # If turned on, we can expect the EMAIL_NOT_ASSOCIATED_WITH_LOGGED_IN_USER to be
        # be returned by org invites if trying to accept when email hasn't been verified.
        if organization.org_invite_email_verification_enabled?
          if errors.any? && accept_status.select { |status| INVITATION_ACCEPTANCE_ERRORS.include?(status.status) }.any?
            return Platform::Provisioning::Result.new \
              external_identity: identity,
              errors: errors
          end
        else
          if errors.any? && accept_status.select { |status| status.status == :user_already_linked }.any?
            return Platform::Provisioning::Result.new \
              external_identity: identity,
              errors: errors
          end
        end

        if invitations.any?
          if restorable.restorable? && can_be_reinstated?(pending_invitations: invitations)
            # Restores the user's org membership in the background
            organization.restore_membership(restorable, actor: identity.user)
            return Platform::Provisioning::Result.pending(external_identity: identity)
          end
        else
          if restorable.restorable?
            # Restores the user's org membership in the background
            organization.restore_membership(restorable, actor: identity.user)
            return Platform::Provisioning::Result.pending(external_identity: identity)
          else
            organization.add_member(identity.user, adder: identity.user)
          end
        end

        success = organization.member?(identity.user)

        if success
          success_status(identity)
        else
          errors << Platform::Provisioning::Error.add_member if errors.empty?

          if !organization.two_factor_requirement_met_by?(identity.user)
            errors << Platform::Provisioning::Error.two_factor_requirement_not_met
          end

          Platform::Provisioning::Result.new \
            external_identity: identity,
            errors: errors
        end
      end

      def self.can_be_reinstated?(pending_invitations: invitations)
        Array(pending_invitations).any? { |invitation| invitation.reinstate? }
      end

      def self.pending_invitations(external_identity:, organization:, token: nil)
        org_invites_associated_with_external_identity = OrganizationInvitation.pending.where(
          external_identity_id: external_identity.id,
          organization_id: organization.id,
        )
        [organization.pending_invitation_for(external_identity.user),
         organization.pending_invitations.find_by_token(token),
         org_invites_associated_with_external_identity,
        ].flatten.compact.uniq
      end

      def self.invite_identity(organization, identity, inviter)
        return internal_provisioning_error_status unless organization && identity && inviter

        invite_status = organization.invite(nil,
            email: identity.scim_user_data.email,
            inviter: inviter,
            role: "reinstate",
            external_identity: identity,
            invitation_source: :scim
          )
        if invite_status.valid?
          success_status(identity)
        else
          Platform::Provisioning::Result.new \
            errors: Platform::Provisioning::Error.invite_identity
        end
      rescue OrganizationInvitation::AlreadyAcceptedError, OrganizationInvitation::InvalidError, ActiveRecord::RecordInvalid => e
        Platform::Provisioning::Result.new \
          errors: Platform::Provisioning::Error.invite_identity(message: e.message)
      rescue OrganizationInvitation::NoAvailableSeatsError => e
        Platform::Provisioning::Result.target_at_seat_limit_error(
          message: "Unable to provision user. The organization #{organization.display_login} has no available seats. Purchase more seats and try again.")
      end

      def self.has_pending_invite_with_different_email?(identity, invitation)
        identity.user.nil? &&
          invitation.present? &&
          invitation.pending? &&
          invitation.email? &&
          identity.scim_user_data.email != invitation.email
      end

      def self.rollback_unless_success(result)
        raise ActiveRecord::Rollback unless result.success?
      end

      # Private: Provisions a new identity and yields it to a block if given
      #
      # organization    - The Organization the identity is under.
      # user            - (Optional) The User the identity is linked to.
      # identity        - (Optional) An existing identity to be updated instead of provisioning
      #                   a new one.
      # user_data       - The Platform::Provisioning::UserData with all of the
      #                   IdP provided data about the user.
      # mapper          - The provisioning mapper responsible for mapping the
      #                   provided user_data to an external identity. This is
      #                   specific for the provisioning scheme (e.g. SAML vs SCIM).
      def self.provision_identity(organization:, identity: nil, user: nil, user_data:, mapper:)
        result = nil

        identity ||= mapper.find_or_build_identity \
            target: organization,
            user: user,
            user_data: user_data
        old_values = mapper.set_user_data(identity: identity, user_data: user_data)

        identity_persisted = identity.persisted?

        ExternalIdentity.transaction do
          result = save_identity(identity, user: user, organization: organization, mapper: mapper)
          rollback_unless_success(result)
        end

        return result unless result.success?

        context = {
          external_identity: identity,
          identity_mapper: mapper.to_s,
          operation: "provision",
          linked_user_id: user.try(:id),
        }

        # Audit log data
        GitHub.context.push context
        Audit.context.push context

        if block_given?
          result = yield(identity)

          unless result.success?
            if identity_persisted
              identity.update!(old_values)
            else
              identity.destroy
            end
          end
        end

        result
      end
    end
  end
end
