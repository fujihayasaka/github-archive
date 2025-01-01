# typed: false
# frozen_string_literal: true

# rubocop:disable GitHub/UsePlatformErrors

module Platform
  module Provisioning
    class IdentityProvisioner

      # raised if IdentityProvisioner methods are invoked for a target Enterprise
      # that doesn't have the `enterprise_idp_provisioning` feature flag enabled.
      class UserProvisioningNotAllowed < StandardError
        def initialize
          super "User Provisioning is not allowed for this Enterprise."
        end
      end

      # Public: Finds an existing identity under the target, based on the data
      #         provided by the IdP.
      #
      # target          - The target the identity is under. Currently only Business
      #                   objects can be targeted.
      # user_data       - The Platform::Provisioning::UserData (or ::GroupData) with all of the
      #                   IdP provided data about the user/group.
      # mapper          - The provisioning mapper responsible for mapping the
      #                   provided user_data to an external identity. This is
      #                   specific for the provisioning scheme (e.g. SAML vs SCIM).
      def self.find(target:, user_data:, mapper: Platform::Provisioning::SamlMapper)
        return invalid_provisioning_target(target: target) unless target.is_a?(Business)

        identity = mapper.find_identity \
          target: target,
          user_data: user_data

        success_status(identity)
      end

      # Public: Updates or provisions an identity under the target.
      #
      # target          - The target the identity is under. Currently only Business
      #                   objects can be targeted.
      # user_id         - (optional) The ID of the User or Organization the identity is linked to.
      # identity_guid   - (optional) The GUID of the external identity to
      #                   provision. If not specified, the mapper will be used
      #                   to find or build one.
      # user_data       - The Platform::Provisioning::UserData (or ::GroupData) with all of the
      #                   IdP provided data about the user/group.
      # mapper          - The provisioning mapper responsible for mapping the
      #                   provided user_data to an external identity. This is
      #                   specific for the provisioning scheme (e.g. SAML vs SCIM).
      # identity              - (optional) The external identity to provision. If not specified
      #                         the mapper will be used to find or build one
      # org_invitation_id     - (optional) The ID of the Organization::Invitation being accepted
      #                         on behalf of the user.
      #
      # Returns: Platform::Provisioning::Result
      def self.provision(target:, user_id: nil, identity_guid: nil, user_data:, mapper:, identity: nil, org_invitation_id: nil)
        return invalid_provisioning_target(target: target) unless target.is_a?(Business)
        return identity_not_found_error_status unless identity_guid.nil? || identity = target.saml_provider.external_identities.where(guid: identity_guid).first
        user = User.find_by id: user_id

        provision_identity(target: target, identity: identity, user: user, user_data: user_data, mapper: mapper) do |identity|
          if org_invitation_id.present?
            # If the lookup fails to find an org invite ID, let the user continue on in the SSO flow without taking any further action. If they have a good return_to param, they should go back to their pending invite and be able to accept it that way.
            org_invitation = OrganizationInvitation.find(org_invitation_id)
            return success_status(identity) if org_invitation.nil? || org_invitation.organization.nil?

            GitHub.logger.info("Accepting SSO invitation during SAML business identity provisioning",
              "gh.business.slug" => target.slug,
              "gh.organization.login" => org_invitation.organization.display_login,
              "gh.user.login" => user&.display_login,
            )

            OrganizationIdentityProvisioner.create_membership(
              identity,
              organization: org_invitation.organization,
            )
          else
            success_status(identity)
          end
        end
      end

      def self.validate_identity_relink(target:, user_id:, user_data:, mapper:)
        return internal_provisioning_error_status unless user = User.find_by_id(user_id)

        mapper.validate_identity_relink \
          target: target,
          user: user,
          user_data: user_data
      end

      # Public: Provisions a new identity under the target for the given user and
      # adds the user to the organizations listed in the SAML `groups` attribute
      #
      # target               - The target the identity is under. Currently only Business
      #                        objects can be targeted.
      # user_id              - (optional) The ID of the User the identity is linked to.
      # identity_guid        - (optional) The GUID of the external identity to
      #                        provision. If not specified, the mapper will be used
      #                        to find or build one.
      # user_data            - The Platform::Provisioning::UserData with all of the
      #                        IdP provided data about the user.
      # mapper               - The provisioning mapper responsible for mapping the
      #                        provided user_data to an external identity. This is
      #                        specific for the provisioning scheme (e.g. SAML vs SCIM).
      # sso_invitation_token - The ID of the Organization::Invitation being accepted
      #                        on behalf of the user.
      #
      # Returns: array of Platform::Provisioning::Result's
      def self.provision_and_add_member(target:, user_id: nil, identity_guid: nil, user_data:, mapper:, sso_invitation_token: nil)
        return invalid_provisioning_target(target: target) unless target.is_a?(Business)
        raise UserProvisioningNotAllowed.new unless enterprise_user_provisioning_enabled?(target: target)
        return identity_not_found_error_status unless identity_guid.nil? || identity = target.saml_provider.external_identities.where(guid: identity_guid).first
        return internal_provisioning_error_status unless user = User.find_by_id(user_id)
        if mapper == Platform::Provisioning::SamlMapper
          # SAML is supposed to send us a current list of the user's groups, so
          # set :received_full_groups_info to true by default
          mapper = Platform::Provisioning::MapperWrapper.new(mapper: mapper,
                                                             received_full_groups_info: true)
        end

        provision_identity(target: target, identity: identity, user: user, user_data: user_data, mapper: mapper) do |identity|
          next success_status(identity) unless target.saml_provider.saml_provisioning_enabled?

          allowed_organizations_args = {
            target: target,
            allowed_organizations: get_allowed_organizations_from_user_data(business: target,
              user_data: user_data, allow_provisioning: target.saml_provider.saml_provisioning_enabled?),
            identity: identity,
            allow_deprovisioning: target.saml_provider.saml_deprovisioning_enabled?,
            actor: user
          }
          results = with_allowed_organizations(**allowed_organizations_args) do |organization|
            OrganizationIdentityProvisioner.create_membership \
              identity, organization: organization, sso_invitation_token: sso_invitation_token
          end

          # TODO - need to devise a way to handle partial successes (able to join org A, but not org B)
          # or roll back the whole operation and fail altogether? For partial success, need to update
          # the error messages to include the name of the organization they were unable to join

          aggregate_results(results, identity)
        end
      end

      # Public: Provisions a new identity in the enterprise, inviting the identity to the list of organizations
      # via the given email address (when present).
      #
      # If the identity is already linked to a user, no invitation is delivered.
      #
      # target          - The target the identity is under. Currently only Business
      #                   objects can be targeted.
      # user_data       - The Platform::Provisioning::UserData with all of the
      #                   IdP provided data about the user. Includes groups which will map to Organization names
      # inviter_id      - The ID of the actor sending the invitation.
      # inviter_type    - The type of the actor sending the invitation (defaults to User).
      # mapper          - The provisioning mapper responsible for mapping the
      #                   provided user_data to an external identity. This is
      #                   specific for the provisioning scheme (e.g. SAML vs SCIM).
      # identity        - In the case of Enterprise SCIM we might have an identity whose `groups` have just been updated
      #                   If so we need to send the identity through the provisioning process to make sure org memberships
      #                   get trued up.
      #
      # Returns: array of Platform::Provisioning::Result's
      def self.provision_and_invite(target:, user_data:, inviter_id:, inviter_type: User, mapper:, identity: nil)
        return invalid_provisioning_target(target: target) unless target.is_a?(Business)
        raise UserProvisioningNotAllowed.new unless enterprise_user_provisioning_enabled?(target: target)
        mapper = Platform::Provisioning::MapperWrapper.new if mapper == Platform::Provisioning::ScimMapper

        provision_identity(target: target, user_data: user_data, mapper: mapper, identity: identity) do |identity|
          next success_status(identity) if identity.user.nil? && identity.scim_user_data.email.blank?

          # if the mapper is going to sync the groups data, then get the organizations just from
          # current user_data, and let the mapper sync the other user_data. If received_full_groups_info?
          # is false, assume the given user_data doesn't have a complete list of groups, so use the
          # identity to get organizations from the groups data in both saml_user_data and
          # scim_user_data
          organizations = if mapper.received_full_groups_info?
            get_allowed_organizations_from_user_data(business: target, user_data: user_data)
          else
            get_allowed_organizations_from_identity(business: target, identity: identity)
          end

          allowed_organizations_args = {
            target: target,
            allowed_organizations: organizations,
            identity: identity,
            # this method is currently only called by SCIM operations, and SCIM de-provisioning is
            # automatically enabled, so just pass true.
            # If SAML operations ever call here, will need to check saml_deprovisioning_enabled?
            allow_deprovisioning: true,
            remove_from_unlinked_orgs: mapper.received_full_groups_info?,
            actor: find_inviter(inviter_id, inviter_type)
          }

          organization_invitation_results = with_allowed_organizations(**allowed_organizations_args) do |organization|
            invite_identity(organization, identity, inviter_id, inviter_type)
          end

          aggregate_results(organization_invitation_results, identity)
        end
      end

      # Public: De-provisions an identity and removes user from the enterprise.
      #
      # target        - The target the identity is under. Currently only Business
      #                 objects can be targeted.
      # user_data     - The Platform::Provisioning::UserData with all of the
      #                 IdP provided data about the user. Optional and will be
      #                 blank for DELETE requests.
      # identity_guid - The guid of the external_identity to be deprovisioned
      # actor_id      - Id of the actor making the deprovision request
      # hard_delete   - If the deprovision request is a "hard delete". This means
      #                 the External identity will not be used again. This parameter is currently
      #                 not used.
      #
      # Returns: Platform::Provisioning::Result
      def self.deprovision(target:, user_data: nil, identity_guid:, actor_id:, hard_delete: false)
        return invalid_provisioning_target(target: target) unless target.is_a?(Business)
        raise UserProvisioningNotAllowed.new unless enterprise_user_provisioning_enabled?(target: target)
        return internal_provisioning_error_status unless target.present?
        return internal_provisioning_error_status unless actor = User.find_by_id(actor_id)

        identity = target.
          saml_provider.
          external_identities.
          with_attributes.
          where(guid: identity_guid).
          first

        return identity_not_found_error_status unless identity.present?
        return cannot_deprovision_self_error_status if identity.user_id == actor_id

        user = identity.user

        invitations = target.
          pending_invitations.
          with_invitee_or_normalized_email(invitee: user, emails: identity.scim_user_data.emails)

        credential_authorizations = Organization::CredentialAuthorization.where \
          actor_id: identity.user_id,
          organization: target.organizations

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

          target.remove_member(user, actor: actor) if user
        end

        GitHub.dogstats.increment("enterprises.scim.deprovision")

        success_status(identity)
      rescue Business::ForbiddenRemovalError, Business::InvalidRemovalError, Organization::NoAdminsError => err
        Platform::Provisioning::Result.new \
          errors: Platform::Provisioning::Error.forbidden_error(message: err.message)
      end

      # Private: processes UserData to ensure that the user/identity is associated with any corresponding
      #     target organizations. Yields a block for each organization that the user/identity should be associated
      #     with for further specific processing (invitations/membership).
      #
      # WARNING! the user's organization membership will be REMOVED if they currently belong to any organizations that
      # are not present in `allowed_organizations`. Each `allowed_organizations` is yielded to a block for specific
      # processing re: inviting a user to an organization or adding them.
      #
      # target: the Business that the identity will be associated with
      # allowed_organizations: the organizations that the identity could be associated with
      # identity: the external identity
      # allow_deprovisioning: flag for whether we can remove users from orgs or not (invitations
      #                       may be cancelled regardless)
      # remove_from_unlinked_orgs: can we remove users from organizations that don't have
      #                            group ExternalIdentity's mapped to them yet?
      # actor: user performing the action - audit log actor for cancelling invitations and
      #        removing org members
      #
      # Returns: array of Platform::Provisioning::Result's
      def self.with_allowed_organizations(target:, allowed_organizations:, identity:,
          allow_deprovisioning:, remove_from_unlinked_orgs: true, actor:)
        raise UserProvisioningNotAllowed.new unless enterprise_user_provisioning_enabled?(target: target)

        user = identity.user
        target_organizations_scope = if remove_from_unlinked_orgs
          target.organizations
        else
          target.organizations.where(id: target.saml_provider.
                                                external_identities.
                                                group_identities.
                                                pluck(:user_id)
          )
        end

        possibly_associated_organizations = OrganizationInvitation
          .where(external_identity: identity, organization: target_organizations_scope)
          .includes(:organization)
          .map(&:organization).to_a.compact.uniq

        if user.present?
          user_organization_logins = (user.invited_organizations + user.organizations).compact.map(&:login) # rubocop:disable GitHub/DoNotAllowLogin - used in a query only
          possibly_associated_organizations = possibly_associated_organizations |
            target_organizations_scope.where(login: user_organization_logins).to_a
        end

        # we have the current target organizations that are associated with the identity/user
        # next we'll compare these to allowed_organizations and see if there are any differences
        # if a current_target_organization exists that's not allowed we'll remove the user/identity
        # we'll then yield all the allowed_organizations to the block
        results = []
        unpermitted_organizations = possibly_associated_organizations - allowed_organizations

        # cancel any unpermitted organization invitations
        invitations_scope = OrganizationInvitation.pending.where(
          external_identity: identity,
          organization: unpermitted_organizations,
        )
        if user.present?
          invitations_scope = invitations_scope.or(
            OrganizationInvitation.pending.where(
              invitee: user,
              organization: unpermitted_organizations
            )
          )
        end
        # REVIEW: for the SAML case, this ends up with the audit log recording that the user has
        # cancelled their own invitation... which is a little confusing (though better than not
        # having an actor for the action at all?)
        # Tracking issue: https://github.com/github/admin-experience/issues/484
        invitations_scope.each { |org_invitation| org_invitation.cancel(actor: actor) }

        if allow_deprovisioning && user.present?
          unpermitted_organizations.each do |unpermitted_organization|
            GitHub.context.push(actor_id: actor.id) do
              unpermitted_organization.remove_member(user,
                background_team_remove_member: true, allow_last_admin_removal: true)
            end
            results << Platform::Provisioning::Result.new(
              external_identity: identity,
              errors: "User deprovisioned from #{unpermitted_organization}",
            )

            GitHub.dogstats.increment("enterprises.scim.remove_org_member")
          end
        end

        results = []
        if block_given?
          allowed_organizations.each do |allowed_organization|
            results << yield(allowed_organization)
          end
        end
        results
      end

      def self.invite_identity(organization, identity, inviter_id, inviter_type)
        return internal_provisioning_error_status unless organization && identity

        # Check if the user is already a member of this org, or if the ExternalIdentity has already
        # been invited via a different email address
        return success_status(identity) if organization.member?(identity.user)
        invitation = OrganizationInvitation.pending.
          find_by(organization: organization, external_identity: identity)
        unless inviter_id.present? || has_pending_invite_with_different_email?(identity, invitation)
          return success_status(identity)
        end

        # can't proceed if no inviter_id present. User is not logged in and coming from SAML.
        # they should be prompted to sign in at which point they'll pass through `provision_and_add_member` which
        # will add them to the target's organizations
        inviter = find_inviter(inviter_id, inviter_type)
        return internal_provisioning_error_status unless inviter

        if invitation
          # API/auth checks should prevent this?
          return internal_provisioning_error_status unless invitation.cancelable_by?(inviter)

          invitation.cancel(actor: inviter)

          # clean up the cancelled invitation's associations
          invitation.update!(external_identity: nil)
          identity.reload
        end

        invitee, email = if identity.user.present?
          [identity.user, nil]
        else
          [nil, identity.scim_user_data.email]
        end
        invite_status = organization.invite(invitee,
          email: email,
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
        target = identity.target

        message = "Unable to provision user. The #{target.name} enterprise has no available seats. Please purchase more seats and try again."

        Platform::Provisioning::Result.target_at_seat_limit_error(message: message)
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

      # Internal: Builds a failed status when we weren't able to provision an identity for the `target`
      # passed.
      #
      # This is not the result of user or IdP error. If this happens, it is a problem on our end.
      def self.invalid_provisioning_target(target:)
        Platform::Provisioning::Result.new \
          errors: Platform::Provisioning::Error.internal_error(
          message: "Unable to provision an identity, #{target} is not an Enterprise account.",
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

      # Internal: Builds a success status
      def self.pending_status(identity)
        Platform::Provisioning::Result.pending(external_identity: identity)
      end

      def self.save_identity(identity, target: nil, user: nil, mapper:)
        if identity.save
          success_status(identity)
        else
          messages = identity.errors.full_messages

          if ExternalIdentity.name_id_already_taken?(identity) &&
            existing_identity = mapper.find_or_build_identity(target: target, user: user, user_data: identity.saml_user_data)
            if existing_identity.persisted?
              messages = [
                "Your GitHub user account @#{user&.display_login} is currently linked to the '#{existing_identity.saml_user_data.name_id}' "\
                "SAML identity. However, you are attempting to authenticate with your Identity Provider using the '#{identity.saml_user_data.name_id}' "\
                "SAML identity which is already linked to a different GitHub user account in the organization. Please reach out to one of your GitHub organization owners for assistance.",
              ]
            end

            Platform::Provisioning::Result.new \
              errors: messages.map { |m| Platform::Provisioning::Error.invalid_identity(message: m) }
          else
            Platform::Provisioning::Result.new \
              errors: messages.map { |m| Platform::Provisioning::Error.bad_request_error(message: m) }
          end
        end
      end

      def self.rollback_unless_success(result)
        raise ActiveRecord::Rollback unless result.success?
      end

      # Private: Provisions a new identity and yields it to a block if given
      #
      # target          - The Business or Organization that the identity is under.
      # user            - (Optional) The User the identity is linked to.
      # identity        - (Optional) An existing identity to be updated instead of provisioning
      #                   a new one.
      # user_data       - The Platform::Provisioning::UserData with all of the
      #                   IdP provided data about the user.
      # mapper          - The provisioning mapper responsible for mapping the
      #                   provided user_data to an external identity. This is
      #                   specific for the provisioning scheme (e.g. SAML vs SCIM).
      def self.provision_identity(target:, identity: nil, user: nil, user_data:, mapper:)
        result = nil

        identity ||= mapper.find_or_build_identity \
          target: target,
          user: user,
          user_data: user_data
        mapper.set_user_data(identity: identity, user_data: user_data)

        ExternalIdentity.transaction do
          result = save_identity(identity, user: user, target: target, mapper: mapper)
          rollback_unless_success(result)

          context = {
            external_identity: identity,
            identity_mapper: mapper.to_s,
            operation: "provision",
            linked_user_id: user.try(:id),
            target: target,
          }

          # Audit log data
          GitHub.context.push context
          Audit.context.push context

          if block_given?
            result = yield(identity)
            rollback_unless_success(result)
          end
        end

        result
      end

      # Private: aggregates the results of several provisioning operations into a single
      # Platform::Provisioning::Result
      #
      # if all the operations had succeeded, returns success_status
      # if any results are pending, returns pending_status
      # if any had failed, returns an error result, which includes all the failures
      #
      # provisioning_results - results of individual provisioning operations
      # identity             - external identity that we were provisioning for
      def self.aggregate_results(provisioning_results, identity)
        failure = false
        pending = false
        provisioning_results.each do |result|
          failure ||= result.errors.any?
          break if failure

          pending ||= result.pending?
        end

        if failure
          failed_result_errors = Set.new
          provisioning_results.reject(&:success?).map do |result|
            result.errors.each do |result_error|
              failed_result_errors.add(result_error)
            end
          end

          Platform::Provisioning::Result.new(external_identity: identity,
                                             errors: failed_result_errors.to_a)
        elsif pending
          pending_status(identity)
        else
          success_status(identity)
        end
      end

      # Private: wrapper for get_allowed_organizations_from_org_logins, which gets the org_logins
      # from the saml_user_data and scim_user_data of the given ExternalIdentity
      #
      # business           - Find Organizations that belong to this Business.
      # identity           - The ExternalIdentity containing the UserData we'll get the groups
      #                      info from
      # allow_provisioning - can we provision an ExternalIdentity for an organization
      #
      # Returns: ActiveRelation of Organizations
      def self.get_allowed_organizations_from_identity(business:, identity:, allow_provisioning: true)
        org_logins = Set.new
        [identity.saml_user_data, identity.scim_user_data].each do |user_data|
          org_logins += business.saml_provider.group_ids(user_data: user_data).keys.compact.uniq
        end

        get_allowed_organizations_from_org_logins(business: business,
                                                  org_logins: org_logins.to_a,
                                                  allow_provisioning: allow_provisioning)
      end

      # Private: wrapper for get_allowed_organizations_from_org_logins, which gets the org_logins
      # from supplied user_data
      #
      # business           - Find Organizations that belong to this Business.
      # user_data          - The Platform::Provisioning::UserData containing the group attributes
      # allow_provisioning - can we provision an ExternalIdentity for an organization
      #
      # Returns: ActiveRelation of Organizations
      def self.get_allowed_organizations_from_user_data(business:, user_data:, allow_provisioning: true)
        org_logins = business.saml_provider.group_ids(user_data: user_data).keys.compact.uniq

        get_allowed_organizations_from_org_logins(business: business,
                                                  org_logins: org_logins,
                                                  allow_provisioning: allow_provisioning)
      end

      # Private: takes a Business and returns all Organizations that the user should be associated
      # with based on the `groups` metadata we've received from the IdP
      #
      # For any Organization found, we'll create a Group ExternalIdentity, if it doesn't already
      # have one, or will update its SamlUserData, if the identity doesn't have any SAML data yet.
      #
      # business           - Find Organizations that belong to this Business.
      # org_logins         - logins of Organizations to retrieve
      # allow_provisioning - can we provision or update an ExternalIdentity for an organization?
      #                      Always true for SCIM operations; depends on the setting for SAML.
      #
      # Returns: ActiveRelation of Organizations
      def self.get_allowed_organizations_from_org_logins(business:, org_logins:, allow_provisioning: true)
        organizations = business.organizations.
          where(login: org_logins).
          includes(:external_identities)

        if allow_provisioning
          organizations.select do |org|
            org.external_identity.nil? || org.external_identity.saml_user_data.none?
          end.each do |organization|
            group_data = Platform::Provisioning::SamlGroupData.load(organization.login) # rubocop:disable GitHub/DoNotAllowLogin - used in a query
            options = {
              target: business,
              user_id: organization.id,
              user_data: group_data,
              mapper: Platform::Provisioning::SamlGroupMapper,
              identity_guid: organization.external_identity&.guid
            }

            provision(**options)
          end
        end

        organizations
      end

      # Private: guard method to ensure we cancel/re-send an invitation when provisioning an identity
      # if an existing OrganizationInvitation exists for a different e-mail address
      def self.has_pending_invite_with_different_email?(identity, invitation)
        identity.user.nil? &&
          invitation.present? &&
          invitation.pending? &&
          invitation.email? &&
          identity.scim_user_data.email != invitation.email
      end

      def self.find_inviter(inviter_id, inviter_type)
        case inviter_type.to_s
        when "IntegrationInstallation"
          if (installation = IntegrationInstallation.find_by(id: inviter_id))
            installation.bot
          end
        when "User"
          User.find_by(id: inviter_id)
        end
      end

      def self.enterprise_user_provisioning_enabled?(target:)
        GitHub.flipper[:enterprise_idp_provisioning].enabled?(target)
      end
    end
  end
end
