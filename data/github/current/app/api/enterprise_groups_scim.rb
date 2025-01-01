# typed: false
# frozen_string_literal: true

class Api::EnterpriseGroupsScim < Api::SCIM::GroupSCIM
  include Api::App::SCIMHelpers

  allow_media SCIM::CONTENT_TYPE

  # Bypass IP allow list enforcement for calls to these endpoints since we do
  # not require an allow list to include the IP addresses of an IdP.
  def ip_allowlist_enforceable
    :no
  end

  get "/scim/v2/enterprises/:enterprise_id/Groups", operation_id: "enterprise-admin/list-provisioned-groups-enterprise" do
    enterprise = find_enterprise!
    enterprise_scim_enabled(enterprise)

    if !GitHub.enterprise?
      control_access :standard_authorization,
        resource: enterprise,
        permission: :read_enterprise_scim,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    else
      control_access :v2_enterprise_scim_writer,
        resource: enterprise,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    end

    if external_groups_enabled?(enterprise)
      get_groups(
        target: enterprise,
      )
    else
      # This does not currently include any group ExternalIdentity's that are not linked to an
      # Organization, which is a case we don't currently support, but may need to in the future
      identities = enterprise.saml_provider.external_identities.group_identities.with_scim_preloads

      if params[:filter]
        identities = begin
            identities.scim_filter(params[:filter])
          rescue SCIM::Filter::InvalidFilterError => e
            # https://tools.ietf.org/html/rfc7644#section-3.12
            deliver_scim_error!(400, scim_type: "invalidFilter", detail: e.message, result: nil)
          end
      end

      results = paginated_results(identities)

      deliver_scim(:enterprise_groups_hash, results, excluded_attributes: params[:excludedAttributes])
    end
  end

  get "/scim/v2/enterprises/:enterprise_id/Groups/:external_identity_guid", operation_id: "enterprise-admin/get-provisioning-information-for-enterprise-group" do
    enterprise = find_enterprise!
    enterprise_scim_enabled(enterprise)

    if !GitHub.enterprise?
      control_access :standard_authorization,
        resource: enterprise,
        permission: :read_enterprise_scim,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    else
      control_access :v2_enterprise_scim_writer,
        resource: enterprise,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    end

    if external_groups_enabled?(enterprise)
      get_group(
        target: enterprise,
      )
    else
      external_identity = enterprise.saml_provider.external_identities.group_identities.
        find_by_guid(params[:external_identity_guid])
      deliver_resource_not_found!(params[:external_identity_guid]) if external_identity.nil?

      deliver_scim(:enterprise_group_hash, external_identity, excluded_attributes: params[:excludedAttributes])
    end
  end

  put "/scim/v2/enterprises/:enterprise_id/Groups/:external_identity_guid", operation_id: "enterprise-admin/set-information-for-provisioned-enterprise-group" do
    enterprise = find_enterprise!
    enterprise_scim_enabled(enterprise)
    block_unsupported_scim_user_agents(enterprise)

    if !GitHub.enterprise?
      control_access :standard_authorization,
        resource: enterprise,
        permission: :write_enterprise_scim,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    else
      control_access :v2_enterprise_scim_writer,
        resource: enterprise,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    end

    if external_groups_enabled?(enterprise)
      update_group(
        target: enterprise,
      )
    else
      external_identity = enterprise.saml_provider.external_identities.group_identities.
        find_by_guid(params[:external_identity_guid])
      deliver_resource_not_found!(params[:external_identity_guid]) if external_identity.nil?
      organization = external_identity.user
      deliver_scim_error!(404, detail: "An unknown error occurred", result: nil) if organization.nil? ||
        organization.soft_deleted?

      json = receive_with_schema("scim-group", "put")
      json_members = Array(json["members"])
      json_guids = json_members.map { |member| member["value"] }

      group_data = Platform::Provisioning::SCIMGroupData.load(json)

      options = {
        target: enterprise,
        user_id: organization.id,
        user_data: group_data,
        mapper: Platform::Provisioning::SCIMGroupMapper,
        identity: external_identity,
      }

      results = []
      results << Platform::Provisioning::IdentityProvisioner.provision(**options)

      identities = enterprise
        .saml_provider
        .external_identities
        .where(guid: json_guids)

      results.concat \
        apply_identity_operation(enterprise, current_user, identities, build_operation("add", organization))

      # we were previously ignoring calls with empty members lists. Switching to process them by
      # default now, unless the :ignore_empty_members feature flag is set for this enterprise.
      process_empty_members_list = !FeatureFlag.vexi.enabled?(:ignore_empty_members, enterprise, default: false)
      if json_members.any? || process_empty_members_list
        cleanup_organization_membership(enterprise: enterprise,
                                        organization: organization,
                                        new_member_identities: identities)
      end

      # allow results.empty? if we bypassed a request with an empty `members` value
      if (results.empty? && process_empty_members_list) || results.all? { |result| result.success? }
        deliver_scim(:enterprise_group_hash, external_identity)
      else
        error_result = results.find { |result| !result.success? }
        # Something went wrong. Scim doesn't specify how to handle general errors
        # so let's just return an error code from result. This should probably be a 422 but SCIM doesn't allow
        # for that https://tools.ietf.org/html/rfc7644#section-3.12
        deliver_scim_error!(error_result&.error_code || 400, detail: error_message_from_results(results), result: error_result)
      end
    end
  end

  # update a group attribute
  patch "/scim/v2/enterprises/:enterprise_id/Groups/:external_identity_guid", operation_id: "enterprise-admin/update-attribute-for-enterprise-group" do
    enterprise = find_enterprise!
    enterprise_scim_enabled(enterprise)
    block_unsupported_scim_user_agents(enterprise)

    if !GitHub.enterprise?
      control_access :standard_authorization,
        resource: enterprise,
        permission: :write_enterprise_scim,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    else
      control_access :v2_enterprise_scim_writer,
        resource: enterprise,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    end

    if external_groups_enabled?(enterprise)
      patch_group(
        target: enterprise,
      )
    else
      json = receive_with_schema("scim-group", "patch")

      external_identity = enterprise.saml_provider.external_identities.group_identities.
        find_by_guid(params[:external_identity_guid])
      deliver_resource_not_found!(params[:external_identity_guid]) if external_identity.nil?
      organization = external_identity.user
      deliver_scim_error!(404, detail: "An unknown error occurred", result: nil) if organization.nil? ||
        organization.soft_deleted?

      results = []

      removed_external_identity_ids = []
      Array(json["Operations"]).each do |scim_operation|
        scim_op = scim_operation.dig("op")&.downcase

        if scim_operation.dig("path")&.start_with?("members")
          # these cases are intentionally WET
          case scim_op
          when "add"
            guids = scim_operation.fetch("value") { [] }.map { |member| member["value"] }
            identities = enterprise
              .saml_provider
              .external_identities
              .where(guid: guids)

            results.concat \
              apply_identity_operation(enterprise, current_user, identities, build_operation("add", organization))
          when "replace"
            guids = scim_operation.fetch("value") { [] }.map { |member| member["value"] }

            # find and update all enterprise external identities not in the list :boom:
            identities_to_remove = enterprise
              .saml_provider
              .external_identities
              .unlinked_or_users
              .where.not(guid: guids)

            remove_operation = build_operation("remove", organization)

            results.concat \
              apply_identity_operation(enterprise, current_user, identities_to_remove, remove_operation)
            removed_external_identity_ids += identities_to_remove.map(&:id)

            # add `organization.login` to `groups` for identities matching guids
            add_operation = build_operation("add", organization)
            identities_to_add = enterprise
              .saml_provider
              .external_identities
              .where(guid: guids)

            results.concat \
              apply_identity_operation(enterprise, current_user, identities_to_add, add_operation)

            cleanup_organization_membership(enterprise: enterprise,
                                            organization: organization,
                                            new_member_identities: identities_to_add)
          when "remove"
            guids = if scim_operation.key?("value")
              scim_operation.fetch("value") { [] }.map { |object| object.dig("value") }
            else
              # an optional syntax
              [scim_operation["path"].scan(/members\[value eq \"(\S+)\"\]/).first&.first]
            end

            identities = enterprise
              .saml_provider
              .external_identities
              .unlinked_or_users
              .where(guid: guids)

            remove_operation = build_operation("remove", organization)
            results.concat \
              apply_identity_operation(enterprise, current_user, identities, remove_operation)
            removed_external_identity_ids += identities.map(&:id)
          else
            # Something went wrong. SCIM doesn't specify how to handle general errors
            # so let's just return a generic 400.
            deliver_scim_error!(400, detail: "Unknown op", result: nil)
          end
        end

        if scim_op == "replace" && scim_operation["path"].in?(%w[externalId displayName])
          patched_group_data = external_identity.scim_group_data
          patched_group_data = SCIM::Operation.apply(patched_group_data, scim_operation)

          options = {
            target: enterprise,
            user_id: organization.id,
            user_data: patched_group_data,
            mapper: Platform::Provisioning::SCIMGroupMapper,
            identity: external_identity,
          }

          results << Platform::Provisioning::IdentityProvisioner.provision(**options)
        end
      end

      error_result = results.find { |result| !result.success? }
      if error_result.nil?
        deliver_scim(:enterprise_group_hash, external_identity)
      else
        # Something went wrong. Scim doesn't specify how to handle general errors
        # so let's just return an error code from result.
        deliver_scim_error!(error_result.error_code, detail: error_message_from_results(results), result: error_result)
      end
    end
  end

  # provision an external identity for a group
  post "/scim/v2/enterprises/:enterprise_id/Groups", operation_id: "enterprise-admin/provision-enterprise-group" do
    enterprise = find_enterprise!
    enterprise_scim_enabled(enterprise, status: 400)
    block_unsupported_scim_user_agents(enterprise)

    if !GitHub.enterprise?
      control_access :standard_authorization,
        resource: enterprise,
        permission: :write_enterprise_scim,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    else
      control_access :v2_enterprise_scim_writer,
        resource: enterprise,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    end

    if external_groups_enabled?(enterprise)
      provision_group(
        target: enterprise,
      )
    else
      json = receive_with_schema("scim-group", "create")
      organization = enterprise.organizations.find_by(login: json["displayName"])
      if organization.nil? || organization.soft_deleted?
        # return success and an empty result list, if matching Organization could not be found -
        # see https://tools.ietf.org/html/rfc7644#section-3.4.2
        halt deliver_scim(:enterprise_groups_hash, paginated_results(ExternalIdentity.none), status: 201)
      end

      group_data = Platform::Provisioning::SCIMGroupData.load(json)
      options = {
        target: enterprise,
        user_id: organization.id,
        user_data: group_data,
        mapper: Platform::Provisioning::SCIMGroupMapper,
      }

      results = []
      results[0] = Platform::Provisioning::IdentityProvisioner.provision(**options)

      if results[0].success?
        json_members = Array(json["members"])
        json_guids = json_members.map { |member| member["value"] }

        identities = enterprise
          .saml_provider
          .external_identities
          .where(guid: json_guids)

        results += apply_identity_operation \
          enterprise, current_user, identities, build_operation("add", organization)

        cleanup_organization_membership(enterprise: enterprise,
                                        organization: organization,
                                        new_member_identities: identities)
      elsif results[0].invalid_identity_error?
        deliver_scim_error!(results[0].error_code, scim_type: "uniqueness", result: results[0])
      end

      error_result = results.find { |result| !result.success? }
      if error_result.nil?
        deliver_scim(:enterprise_group_hash, results[0].external_identity, status: 201)
      else
        # Something unexpected happened. SCIM doesn't define a general error so
        # we'll just respond with an error code from result.
        GitHub.logger.error({
          "exception.type" => error_result.errors.first.reason,
          "exception.message" => error_result.error_messages,
          "gh.business.id" => enterprise.id
        })
        deliver_scim_error!(error_result.error_code, detail: error_message_from_results([error_result]), result: error_result)
      end
    end
  end

  # deprovision a group
  delete "/scim/v2/enterprises/:enterprise_id/Groups/:external_identity_guid", operation_id: "enterprise-admin/delete-scim-group-from-enterprise" do
    enterprise = find_enterprise!
    enterprise_scim_enabled(enterprise)
    block_unsupported_scim_user_agents(enterprise)

    if !GitHub.enterprise?
      control_access :standard_authorization,
        resource: enterprise,
        permission: :write_enterprise_scim,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    else
      control_access :v2_enterprise_scim_writer,
        resource: enterprise,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    end

    if external_groups_enabled?(enterprise)
      delete_group(
        target: enterprise,
      )
    else
      # linters
      receive_with_schema("scim-group", "delete")

      external_identity = enterprise.saml_provider.external_identities.group_identities.
        find_by_guid(params[:external_identity_guid])
      deliver_resource_not_found!(params[:external_identity_guid]) if external_identity.nil?
      organization = external_identity.user
      deliver_scim_error!(404, detail: "An unknown error occurred", result: nil) if organization.nil?

      results = deprovision_scim_group(enterprise, group_identity: external_identity)

      error_result = results.find { |result| !result.success? }
      if error_result.nil?
        deliver_empty status: 204
      else
        # Something went wrong. SCIM doesn't specify how to handle general errors
        # so let's just return an error code from result.
        deliver_scim_error!(error_result.error_code, detail: error_message_from_results(results), result: error_result)
      end
    end
  end

  private

  # Private: Check weather the environment called is enabled for external group SCIM
  #
  # enterprise          - Enterprise where SAML is enabled
  #
  # Returns Boolean
  def external_groups_enabled?(enterprise)
    return true if enterprise.enterprise_server_scim_enabled?
    enterprise.enterprise_managed_user_enabled?
  end

  # Private: applies the SCIM::Operation `operation` passed in to the list of `identities`
  #
  # enterprise          - Enterprise where SAML is enabled
  # current_user        - user performing the action
  # identities          — an Enumerable of ExternalIdentity records to be updated
  # operation           — a SCIM::Operation directive created by `build_operation`
  # mapper              - the mapper to use for applying this operation
  #
  # returns an Array of Platform::Provisioning::Result instances
  def apply_identity_operation(enterprise, current_user, identities, operation,
                               mapper: Platform::Provisioning::ScimMapper)
    identities.map do |identity|
      mapper_wrapper = Platform::Provisioning::MapperWrapper.new(mapper: mapper)
      patched_active_user_data = mapper_wrapper.apply_operation_to_identity(identity, operation)
      options = {
        target: enterprise,
        user_data: patched_active_user_data,
        inviter_id: current_user.id,
        mapper: mapper_wrapper,
        identity: identity,
      }

      # If the request is being performed by an app
      # we need to pass along the `IntegrationInstallation`
      # record as the inviter instead of the `Bot`.
      if current_user.bot?
        options[:inviter_id]   = current_user.installation.id
        options[:inviter_type] = IntegrationInstallation
      end

      Platform::Provisioning::IdentityProvisioner.provision_and_invite(**options)
    end
  end

  # Private: helper method to clean up organization's membership after a SCIM operation.
  #   Does the following:
  #    - finds all the ExternalIdentity's associated with the organization that are not supposed to
  #      be, removes the org reference in their user_data's and removes their users from the org
  #      We suppress the "Can't remove the last admin" exception by passing the
  #      `allow_last_admin_removal` flag. (or cancels invitations, if user hasn't accepted yet)
  #    - removes members who were not provisioned by the IdP
  #    - cancels invitations to members who were not provisioned by the IdP
  #
  # enterprise               - parent enterprise where SAML is defined
  # organization             — the organization whose membership we're updating
  # new_member_identities    - ExternalIdentity's representing the current member list,
  #                            according to the IdP
  # actor                    - used for the audit log entry for cancelling invitations
  # external_identities_only - only cleans up users who have external identities if true,
  #             removes/un-invites any users who don't have external identities otherwise
  #
  # Returns: array of Platform::Provisioning::Result's
  def cleanup_organization_membership(enterprise:, organization:, new_member_identities:,
                                      actor: current_user, external_identities_only: false)
    member_identities = enterprise.saml_provider.external_identities_for_organization(organization)
    identities_to_remove = member_identities.where.not(id: new_member_identities.map(&:id))
    remove_operations = build_remove_operations(organization, identities_to_remove)

    results = remove_operations[:scim].map do |remove_operation|
      identities_to_remove_scim = identities_to_remove.provisioned_by(:scim)
      apply_identity_operation(enterprise, actor, identities_to_remove_scim,
                               remove_operation)
    end.flatten

    results += remove_operations[:saml].map do |remove_operation|
      identities_to_remove_saml = identities_to_remove.provisioned_by(:saml)
      apply_identity_operation(enterprise, actor, identities_to_remove_saml,
                               remove_operation, mapper: Platform::Provisioning::SamlMapper)
    end.flatten

    unless external_identities_only
      org_member_ids = organization.member_ids - member_identities.map(&:user_id)

      if organization.business&.erp_feature_enabled?(:enterprise_teams_org_assignment)
        User.where(id: org_member_ids).each do |member|
          begin
            organization.remove_member(member, allow_last_admin_removal: true)
          rescue Organization::BusinessTeamsDependency::UnableToRemoveBusinessTeamMemberError
            GitHub.logger.warn("Unable to remove member from organization because part of an enterprise team",
              "gh.organization.id": organization.id,
              "gh.user.id": member.id,
            )
          end
        end
      else
        User.where(id: org_member_ids).map do |member|
          organization.remove_member(member, allow_last_admin_removal: true)
        end
      end

      organization.pending_invitations.where(external_identity_id: nil).each do |invitation|
        invitation.cancel(actor: actor)
      end
    end

    results
  end

  # Private: perform necessary cleanup when the IdP tells us to delete a SCIM group. Note: we
  # are not going to actually delete the GitHub organization, and we don't want to assume that
  # the group is altogether removed from the IdP. We just want to remove the SCIM links to this
  # group and remove any members who were added or invited to it via SCIM. SAML-provisioned
  # members get to stay - if the group is really removed in the IdP, they will be removed from
  # the organization the next time they SSO.
  #
  # enterprise     - parent enterprise where SAML is defined
  # group_identity - ExternalIdentity of the org that the IdP wants to delete
  #
  # This becomes a bit of a hacky mess... because the IdP is telling us to destroy the SCIM link
  # to this organization, but isn't telling us anything about SAML. So, we do the following:
  #  - remove any user identities that were attached to this group only via SCIM (in reality, this
  #       only affects invitations, as users have to go through SAML SSO in order to accept an
  #       invitation)
  #  - remove any SCIM group attributes in user identities that point to this group. We'd already
  #       made sure to remove any SCIM-only user identities from this org, so this is just cleanup
  #       for identities which have both SAML and SCIM data pointing to this org/group
  #  - cleanup the group external identity: destroy it if there's no SAML group data, or leave it
  #       in place and just remove the SCIM group data, if SAML group data is present
  #
  # Note: there's one case we're not handling here: we can have SAML-provisioned user external
  # identities that reference a group by its SCIM external_id, instead of the org login. That
  # relationship would get broken when the scim_user_data for the group external identity is
  # destroyed. We could try and fix that case, but have so far decided to hold off on it, since it
  # only appears to happen with AAD, and we're still ironing out full support for AAD Provisioning.
  # More detail and discussion: https://github.com/github/github/pull/152290#issuecomment-676745075
  #
  # Returns: array of Platform::Provisioning::Result's
  def deprovision_scim_group(enterprise, group_identity:)
    organization = group_identity.user

    [# Remove any SCIM-only user identities associated with this group
     remove_scim_identities_from_group(enterprise, organization),
     # Clean up remaining identities for this org: remove SCIM references to this group
     #
     # Enterprise SCIM V1 is not available in Proxima therefore safe to use login here.
     remove_group_references(enterprise, group_name: organization.login), # rubocop:disable GitHub/DoNotAllowLogin
     # Clean up the group's external identity
     cleanup_group_identity(group_identity)].flatten
  end

  # Private - remove any SCIM-only user identities from this organization, if the IdP has sent
  # us a DELTE SCIM message
  #
  # enterprise    -   parent enterprise where SAML is defined
  # organization  -   organization to update
  #
  # Returns: array of Platform::Provisioning::Result's
  def remove_scim_identities_from_group(enterprise, organization)
    saml_identities = enterprise.saml_provider.
      external_identities_for_organization(organization).
      provisioned_by(:saml)
    # remove any identities from this group that are not in saml_identities
    cleanup_organization_membership(enterprise: enterprise,
                                    organization: organization,
                                    new_member_identities: saml_identities,
                                    external_identities_only: true)
  end

  # Private: remove references to an IdP group from ScimUserData attached to any of the
  # ExternalIdentity's attached to the given enterprise
  #
  # enterprise    -   parent enterprise where SAML is defined
  # group_name    -   name of the IdP group to delete
  #
  # Returns: array of Platform::Provisioning::Result's
  def remove_group_references(enterprise, group_name:)
    scim_user_data = Platform::Provisioning::ScimUserData.new \
      [{ "name" => "groups", "value" => group_name }]

    scim_identities_with_group = enterprise.saml_provider.external_identities.by_scim_user_data(scim_user_data)

    scim_identities_with_group.map do |identity|
      patched_user_data = identity.scim_user_data
      patched_user_data.delete_if do |attr|
        attr["name"] == "groups" && attr["value"] == group_name
      end

      Platform::Provisioning::ScimMapper.set_user_data(identity: identity,
                                                       user_data: patched_user_data)
      result_status(identity.save, identity)
    end
  end

  # Private: Destroy or clean up the group's ExternalIdentity. If the identity has SAML data, then
  # just remove the SCIM data from it. If there's no SAML data, destroy the identity.
  #
  # group_identity    -   ExternalIdentity for an org whose group is being deleted
  #
  # Returns: Platform::Provisioning::Result
  def cleanup_group_identity(group_identity)
    if group_identity.saml_group_data.none?
      group_identity.destroy

      result_status(true, group_identity)
    else
      Platform::Provisioning::SCIMGroupMapper.set_user_data \
        identity: group_identity, user_data: Platform::Provisioning::SCIMGroupData.new

      result_status(group_identity.save, group_identity)
    end
  end

  # Private: helper method to generate a Platform::Provisioning::Result from a boolean flag
  #
  # success       -   did the operation succeed?
  # identity      -   ExternalIdentity to associate this result with
  # error_message -   error message to add if operation did not succeed
  #
  # Returns: Platform::Provisioning::Result
  def result_status(success, identity, \
    error_message: "An internal error has occurred: unable to update the group's external identity.")
    if success
      Platform::Provisioning::Result.success(external_identity: identity)
    else
      Platform::Provisioning::Result.new \
          errors: Platform::Provisioning::Error.internal_error(
          message: error_message,
          )
    end
  end

  # Private: helper method to return the first error message from an array of
  # Platform::Provisioning::Result objects. If there is more than one Result with an error,
  # will return the error message from the first one in the array.
  #
  # results   -   array of Platform::Provisioning::Result's
  #
  # Returns: A String containing the error messages from the first Result that wasn't a success.
  def error_message_from_results(results)
    return "An unknown error occurred" if results.empty?

    error_result = results.find { |result| !result.success? }
    return "" if error_result.nil?

    error_result.error_messages.join(", ")
  end

  # Private: helper method for building the objects that we'll need to fully clean up group
  # membership information for ExternalIdentity's.
  # An ExternalIdentity is connected to a group (organization) if it has a 'group'
  # ExternalIdentityAttribute for a group, whose value references the organization.
  # Possible combinations:    attribute name        value
  #             Okta SCIM:       groups             organization login
  # Okta SCIM (alternate):       groups             organization identity external_id
  #             Okta SAML:       groups             organization login
  #              AAD SCIM:       groups             organization login
  #              AAD SAML:       http://schemas.microsoft.com/ws/2008/06/identity/claims/groups
  #                                                 organization identity external_id
  # organization - organization that the identities are being removed from
  # identities_to_remove - identities we need to remove
  #
  # Returns: Hash of operations that SCIM::Operation.apply can use to remove all references to
  # the organization for each of the identities specified.
  def build_remove_operations(organization, identities_to_remove)
    operations = { scim: [], saml: [] }
    identities_to_remove_scim = identities_to_remove.provisioned_by(:scim)
    if identities_to_remove_scim.any?
      operations[:scim] = [
        build_operation("remove", organization),
        build_operation_with_value("remove",
          organization.external_identity.scim_user_data.external_id)
      ]
    end

    identities_to_remove_saml = identities_to_remove.provisioned_by(:saml)
    if identities_to_remove_saml.any?
      operations[:saml] = [
        build_operation("remove", organization),
        build_operation_with_value("remove",
          organization.external_identity.scim_user_data.external_id,
          groups_path: "http://schemas.microsoft.com/ws/2008/06/identity/claims/groups")
      ]
    end

    operations
  end

  # Private: helper method for building an object which causes an op to be applied to an external
  # identity's `groups` metadata
  #
  # op - the SCIM::Operation to perform, `add`, `remove`, or `replace`
  # organization - the organization whose login should be added, removed, or replaced
  # groups_path - value to use for the groups path
  #
  # Returns: Hash suitable for SCIM::Operation.apply
  def build_operation(op, organization, groups_path_value: "groups")
    # Enterprise SCIM V1 is not available in Proxima therefore safe to use login here.
    build_operation_with_value(op, organization.login, groups_path: groups_path_value) # rubocop:disable GitHub/DoNotAllowLogin
  end

  def build_operation_with_value(op, group_value, groups_path: "groups")
    {
      "op" => op,
      "path" => groups_path,
      "value" => {
        groups_path => [{
          "value" => group_value,
        }],
      },
      "meta" => {
        "groups_path_key" => groups_path,
      }
    }
  end
end
