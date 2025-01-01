# typed: false
# frozen_string_literal: true
# rubocop:disable GitHub/UsePlatformErrors

module Platform
  module Provisioning
    class EnterpriseServerIdentityProvisioner
      extend GitHub::Authentication::UserHandler

      include Platform::Provisioning::OperationType

      EMAILS_EMPTY = "External authentication provided an empty email attribute. Please have your administrator check the authentication log."
      EMAIL_TAKEN = "Another user already owns the email. Please have your administrator check the authentication log."
      LOGIN_CONFLICT = "Another user already owns the account. Please have your administrator check the authentication log."
      MISSING_LOGIN = "The response did not contain either a valid NameID or a valid configured Username attribute."
      ORGANIZATION_CONFLICT = "Cannot authenticate as an Organization"
      USER_SUSPENDED = "Your account has been suspended. Please contact your Enterprise administrator to request access."

      # raised if IdentityProvisioner methods are invoked when a target Enterprise
      # isn't the GHES Global Business
      class UserProvisioningNotAllowed < StandardError
        def initialize
          super "User Provisioning is not allowed for this Enterprise."
        end
      end

      # Public: Provisions a new identity on the instance.
      #
      # target          - The target the identity is under. Defaults to the GitHub.global_business
      # user_id         - (optional) The ID of the User the identity is linked to.
      # identity_guid   - (optional) The GUID of the external identity to
      #                   provision. If not specified, the mapper will be used
      #                   to find or build one.
      # user_data       - The Platform::Provisioning::UserData with all of the
      #                   IdP provided data about the user.
      # mapper          - The provisioning mapper responsible for mapping the
      #                   provided user_data to an external identity. This is
      #                   specific for the provisioning scheme (e.g. SAML vs SCIM).
      def self.provision_and_add_member(target: GitHub.global_business, user_id: nil, identity_guid: nil, user_data:, mapper:)
        provision_identity(target: target, user_data: user_data, mapper: mapper) do |_identity|
          login = user_data.user_name

          next self.missing_login_status if login.blank?

          result = self.find_or_create_user(user_data, login)
          next result unless result.success?

          user = result.user

          # Reconcile suspension status
          self.reconcile_access(user)

          next user_suspended_status(result.external_identity) if user.suspended?

          next result
        end
      end

      # Public: Updates or provisions an identity under the target.
      #
      # target_id       - The target the identity is under. Currently Business and Organization
      #                   objects can be targeted.
      # user_id         - (optional) The ID of the User the identity is linked to.
      # identity_guid   - (optional) The GUID of the external identity to
      #                   provision. If not specified, the mapper will be used
      #                   to find or build one.
      # user_data       - The Platform::Provisioning::UserData with all of the
      #                   IdP provided data about the user.
      # mapper          - The provisioning mapper responsible for mapping the
      #                   provided user_data to an external identity. This is
      #                   specific for the provisioning scheme (e.g. SAML vs SCIM).
      # identity        - (optional) The external identity to provision. If not specified
      #                   the mapper will be used to find or build one
      def self.provision(target:, user_id: nil, identity_guid: nil, user_data:, mapper:, identity: nil)
        return invalid_provisioning_target(target: target) unless target.is_a?(Business)
        identity ||= identity_guid.present? && target.saml_provider.external_identities.where(guid: identity_guid).first
        return identity_not_found_error_status unless identity_guid.nil? || identity.present?
        user = User.find_by id: user_id

        provision_identity(target: target, identity: identity, user: user, user_data: user_data, mapper: mapper) do |identity|
          User.transaction do
            action = push_to_context(operation: UPDATE)

            if user_data.active? && identity.user.suspended?
              action = push_to_context(operation: UNSUSPEND)

              result = identity.user.unsuspend(
                "has been provisioned via SCIM"
              )
              next internal_provisioning_error_status unless result
            end

            result = identity.enable
            next internal_provisioning_error_status unless result

            # reconcile user data
            if identity.user
              result = update_user(identity.user, user_data, reason: action)
              next result unless result.success?
            end

            success_status(identity, audit_event: action)
          end
        end
      end

      # Public: Provisions a new identity on the instance.
      #
      # If the user account is already provisioned, no invitation is delivered.
      #
      # target          - The Business to provision users into
      # user_data       - The Platform::Provisioning::UserData with all of the
      #                   IdP provided data about the user.
      # inviter_id      - The ID of the actor sending the invitation.
      # inviter_type    - The type of the actor sending the invitation (defaults to User).
      # mapper          - The provisioning mapper responsible for mapping the
      #                   provided user_data to an external identity. This is
      #                   specific for the provisioning scheme (e.g. SAML vs SCIM).
      def self.provision_and_invite(target:, user_data:, inviter_id:, inviter_type: User, mapper:)
        return invalid_provisioning_target(target: target) unless target.is_a?(Business) && !GitHub.enterprise_first_run?

        provision_identity(target: target, user_data: user_data, mapper: mapper) do |identity|
          User.transaction(requires_new: true) do
            begin
              scim_username = user_data.user_name

              # This will normalize the username and search for it.
              user, message = self.find_legacy_user(scim_username, user_data)

              # return invalid_identity_error if the user already exists and is not linked in the Enterprise,
              # or if message indicates this is an org
              next self.login_conflict_status if user && !valid_to_link_scim_identity?(user, identity)

              if message
                next Platform::Provisioning::Result.new \
                  errors: Platform::Provisioning::Error.invalid_identity(
                    message: message,
                  )
              end

              # create a user unless the user already exists and is linked to the Enterprise
              # this is validated above
              unless user
                user, message = self.create_user(scim_username, user_data)
                next create_user_status(message) if message
              end

              # reconcile user data
              if user
                result = update_user(user, user_data, reason: PROVISION)
                next result unless result.success?
              end

              next create_user_status("The user could not be created from the provided attributes.") unless user.valid?

              identity.user = user
              success_status(identity, audit_event: :provision)
            rescue ActiveRecord::RecordInvalid
              # this is a just-in-case rescue, since we check for user.valid? before saving
              next internal_provisioning_error_status
            end
          end
        end
      end

      # Public: De-provisions an identity and removes user from the enterprise.
      #
      # target        - The enterprise that the identity is under.
      # user_data     - The Platform::Provisioning::UserData with all of the
      #                 IdP provided data about the user. Optional and will be
      #                 blank for DELETE requests.
      # identity_guid - The guid of the external_identity to be deprovisioned
      # actor_id      - Id of the actor making the deprovision request
      # hard_delete   - If the deprovision request is a "hard delete". This means
      #                 the External identity will not be used again.
      def self.deprovision(target:, user_data: nil, identity_guid:, actor_id:, hard_delete: false)
        return invalid_provisioning_target(target: target) unless target.is_a?(Business) && !GitHub.enterprise_first_run?

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
        return internal_provisioning_error_status unless user

        context = {
          external_identity: identity,
          operation: "deprovision",
          identity_mapper: Platform::Provisioning::ScimMapper.to_s,
        }

        GitHub.context.push context
        Audit.context.push context

        action = nil
        result = provision_identity(target: target, identity: identity, user: user, user_data: user_data, mapper: Platform::Provisioning::ScimMapper) do |identity|
          User.transaction do
            action = push_to_context(operation: SUSPEND) unless hard_delete
            action = push_to_context(operation: DELETE) if hard_delete

            unless user.suspended?
              result = user.suspend(
                "has been deprovisioned via SCIM",
                actor: actor,
                instrument_abuse_classification: false,
              )
              next internal_provisioning_error_status unless result
            end

            result = identity.disable
            next internal_provisioning_error_status unless result

            if hard_delete
              result = identity.mark_deleted
              next internal_provisioning_error_status unless result

              if user
                delete_user_attributes(user)
                user.rebuild_contributions
              end
            end

            success_status(identity, audit_event: action)
          end
        end

        # Process all PATCH attributes when deprovisioning user
        update_user(user.reload, user_data, reason: action) if user_data.present?

        return internal_provisioning_error_status unless user.reload.suspended?
        result
      end

      # Takes a SAML Assertion (in the form of UserData) and either finds the associated
      # user account, or creates one.
      # Returns a Platform::Provisioning::Result
      def self.find_or_create_user(user_data, login)
        name_id = user_data.name_id
        name_id_format = user_data.name_id_metadata["Format"] unless name_id.nil?

        result = nil
        User.transaction do
          begin
            mapping = find_saml_mapping(name_id, login, name_id_format)
            action = push_to_context(operation: PROVISION)

            if mapping
              action = push_to_context(operation: UPDATE)

              result = update_user(mapping.user, user_data, reason: action)
              rollback_unless_success(result)
              if has_custom_username_attribute?
                mapping.migrate_mapping!(name_id, login)
              end

              result = success_status(mapping, audit_event: action)
            else
              user, message = self.find_legacy_user(login, user_data)

              if message == ORGANIZATION_CONFLICT
                result = org_conflict_status
              elsif user&.saml_mapping
                # If the earlier look up succeeded, the normalized login is already
                # taken. Bail out and inform the user of the clash.
                result = login_conflict_status
              else
                # If we're here, and no existing user has been found and no error
                # message was returned, create a new user
                user, message = self.create_user(login, user_data) if user.nil? && message.nil?

                if message
                  result = create_user_status(message)
                elsif user
                  result = update_user(user, user_data, reason: action)
                  rollback_unless_success(result)
                  saml_mapping = map_saml_entry(name_id, name_id_format, user.id)

                  result = success_status(saml_mapping, audit_event: action)
                else
                  # This shouldn't happen. Reuse internal_provisioning_status for now.
                  result = internal_provisioning_error_status
                end
              end
            end
          rescue ActiveRecord::RecordInvalid => e
            raise ActiveRecord::Rollback
          end
        end

        result
      end

      # Override UserHandler#find_user to avoid provisioning error when NameID
      # is an email.
      #
      # https://github.com/github/enterprise2/issues/2936
      def self.find_legacy_user(uid, entry)
        if uid["@"]
          login = User.standardize_login(uid)
          user = User.find_by_login(login)
          if user
            return [nil, ORGANIZATION_CONFLICT] if user.organization?
            return [user, nil]
          end
        end

        self.find_user(uid, entry)
      end

      # Strategy to find the user corresponding to the SamlResponse
      #
      # 1. find by name_id. nameid-format has to match
      # 2. find by login. nameid-format has to match
      # 3. To address https://github.com/github/github/issues/90447,
      #    relax checking by name-id-format if requests are sent with unspecified,
      #    1. find by name_id
      #    2. find by login
      def self.find_saml_mapping(name_id, login, name_id_format)
        result = SamlMapping.by_name_id_and_name_id_format(name_id, name_id_format)
        return result if result.present?
        result = SamlMapping.by_name_id_and_name_id_format(login, name_id_format)
        return result if result.present?
        # if instance is configured to send request with unspecified, relax the search
        if name_id_format_unspecified?
          result = SamlMapping.find_by(name_id: name_id)
          return result if result.present?
          result = SamlMapping.find_by(name_id: login)
          return result if result.present?
        end
      end

      # Public - Create a mapping between the user and the SAML NameID or
      # claim/name or claim/emailaddress in the case of a transient NameID and
      # keep a record of this.
      # It also updates the mapping when it exists.
      #
      # name_id: is the raw SAML NameID attribute or claim/name or claim/emailaddress from the SAML response.
      # name_id_format: is the format of the SAML response.
      # user_id: is the ID of the logged in User.
      #
      # Returns true if the mapping was created.
      def self.map_saml_entry(name_id, name_id_format, user_id)
        SamlMapping.by_name_id_and_name_id_format(name_id, name_id_format) || SamlMapping.create(user_id: user_id, name_id: name_id, name_id_format: name_id_format)
      rescue ActiveRecord::RecordNotUnique
        # we don't care if the insert fails due to dupe key violation
        true
      end

      # Private: User update callback after scim delete
      #
      # Removes emails, ssh keys and gpg keys of the user account
      #
      # Returns nothing.
      def self.delete_user_attributes(user)
        user.email_roles.delete_all
        user.emails.destroy_all

        user.public_keys.destroy_all
        user.oauth_accesses.destroy_all
        user.gpg_keys.destroy_all

        #remove saml_mapping if it exists since NameId has uniqueness constraint
        user.saml_mapping&.delete
      end

      # Private: User update callback after success authentication
      #
      # Returns Platform::Provisioning::Result
      def self.update_user(user, user_data, reason: :create_user)
        result = Platform::Provisioning::UserDataReconciler.reconcile(
          user,
          user_data,
          reason: reason,
          flags: { is_enterprise_server: true },
        )

        # just check for fatal email (when primary email is taken it will be set)
        if result.errors[:emails]&.fatal?
          return Platform::Provisioning::Result.new(errors: result.error_message(:emails))
        end

        # returns always result with no errors for GHES
        Platform::Provisioning::Result.new(errors: [])
      end

      def self.has_custom_username_attribute?
        attribute_mappings[:user_name].present?
      end

      # Reconciles access by suspending or unsuspending the User record
      # when appropriate.
      #
      # user: User object to reconcile
      def self.reconcile_access(user)
        if user.suspended? && GitHub.reactivate_suspended_user?
          user.unsuspend("is granted access in SAML IdP")
        end
      end

      # Mapping from name of attribute to idP configured attribute name. This
      # will be replaced with constant values rather than configurable values.
      def self.attribute_mappings
        GitHub.auth.attribute_mappings
      end

      # determine if the running instance is configured to send SamlRequests with nameid-format=unspecified
      def self.name_id_format_unspecified?
        name_id_format = GitHub.auth.configuration[:name_id_format]
        return true unless name_id_format.present? # if not set, it defaults to unspecified
        name_id_format == "urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified"
      end

      # Internal: Builds a success status
      def self.success_status(identity, audit_event: nil)
        Platform::Provisioning::Result.success(external_identity: identity, audit_event: audit_event)
      end

      # Internal: Builds a failed status when a user could not be created
      def self.create_user_status(message)
        Platform::Provisioning::Result.new \
          errors: Platform::Provisioning::Error.new(
            reason: :create_user,
            message: message
          )
      end

      # Internal: Builds a failed status when the emails attribute in the SAML Assertion is
      # empty
      def self.email_empty_status
        Platform::Provisioning::Result.new \
          errors: Platform::Provisioning::Error.new(
            reason: :emails_empty,
            message: EMAILS_EMPTY
          )
      end

      # Internal: Builds a failed status when the email provided in the SAML Response
      # is already taken by another user.
      def self.email_taken_status
        Platform::Provisioning::Result.new \
          errors: Platform::Provisioning::Error.new(
            reason: :email_taken,
            message: EMAIL_TAKEN
          )
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
      def self.invalid_provisioning_target(target:)
        Platform::Provisioning::Result.new \
          errors: Platform::Provisioning::Error.internal_error(
            message: "Unable to provision an identity, #{target} is not valid for provisioning.",
        )
      end

      # Internal: Builds a failed status when the fallback login calculated
      # from the SAML response is already mapped to a user.
      def self.login_conflict_status
        Platform::Provisioning::Result.new \
          errors: Platform::Provisioning::Error.invalid_identity(
            message: LOGIN_CONFLICT,
          )
      end

      def self.missing_login_status
        Platform::Provisioning::Result.new \
        errors: Platform::Provisioning::Error.new(
          reason: :missing_login,
          message: MISSING_LOGIN
        )
      end

      # Internal: Builds a failed status when the mapped user from the SAML
      # Response is an organization
      def self.org_conflict_status
        Platform::Provisioning::Result.new \
          errors: Platform::Provisioning::Error.new(
            reason: :organization_conflict,
            message: ORGANIZATION_CONFLICT
          )
      end

      # Internal: Builds a failed status when the user has been found, but could
      # not be automatically unsuspended.
      def self.user_suspended_status(identity)
        Platform::Provisioning::Result.new \
          external_identity: identity,
          errors: Platform::Provisioning::Error.new(
            reason: :user_suspended,
            message: USER_SUSPENDED
          )
      end

      def self.save_identity(identity, target: nil, user: nil, mapper:)
        if identity.save
          success_status(identity)
        else
          # there was an issue saving the identity
          messages = identity.errors.full_messages

          Platform::Provisioning::Result.new \
            errors: messages.map { |m| Platform::Provisioning::Error.invalid_identity(message: m) }
        end
      end

      def self.rollback_unless_success(result)
        raise ActiveRecord::Rollback unless result.success?
      end

      # Private: circumstances in which a SCIM create can link to an existing user
      def self.valid_to_link_scim_identity?(user, identity)
        # link to an existing SAML identity
        return true if user && identity.user == user

        # allow linking to a new identity unless user already has a linked identity
        provider = identity.provider
        existing_identity = ExternalIdentity.by_provider(provider).not_deleted.linked_to(user).first

        # allow linking to an existing user if:
        # - This is a new, unlinked indentity
        # - There is no existing identity linked to the user
        return true if user && identity.user.nil? && existing_identity.nil?

        false
      end

      # Private: Push operation to context
      #
      # Returns operation pushed
      def self.push_to_context(operation:)
        # Audit log data
        GitHub.context.push operation: operation
        Audit.context.push operation: operation

        operation
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

        yield
      end

      # Internal: Builds a failed status when the provisioning was not enabled
      # TODO: Remove duplicate method definition once we convert this file to use
      #       Platform::Provisioning::BaseIdentityProvisioner
      def self.provisioning_not_enabled(message)
        Platform::Provisioning::Result.new \
          errors: Platform::Provisioning::Error.new(
            reason: :provisioning_not_enabled,
            message: message
          )
      end
    end
  end
end
