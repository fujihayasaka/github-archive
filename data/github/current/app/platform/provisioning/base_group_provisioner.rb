# typed: false
# frozen_string_literal: true
# rubocop:disable GitHub/UsePlatformErrors

class Platform::Provisioning::BaseGroupProvisioner < Platform::Provisioning::ProvisionerStatus
  include BusinessesHelper

  DUPLICATE_MEMBERSHIP_FOUND = "The membership being added already exists."

  # Public: Finds all external group records for a target
  #
  # target          - The target the identity is under. Business or organization.
  #
  # Returns Result record
  def self.find_all(
    target:
  )
    return internal_error_status \
      unless target.present? && target.external_provider.present?

    groups = new(target: target, mapper: nil, group_data: nil).
      find_all_groups

    success_group_status(groups)
  end

  # Public: Find the external group record. If the Group GUID was provided it is used to
  #  exactly match it, otherwise the data from the user_data is used through a mapper.
  #
  # target          - The target the group is under. Business or organization.
  # group_guid      - (optional) The GUID of the external group to
  #                   find.
  # group_data      - The Platform::Provisioning::SCIMGroupData with all of the
  #                   IdP provided data about the group.
  # mapper          - The provisioning mapper responsible for mapping the
  #                   provided group_data to an external group. This is
  #                   specific for the provisioning scheme (e.g. SAML vs SCIM).
  #
  # Returns Result record
  def self.find(
    target:,
    group_guid: nil,
    group_data: nil,
    mapper: nil,
    exclude_members: true
  )
    return internal_error_status \
      unless target.present? && target.external_provider.present?
    return internal_error_status unless mapper.present? || group_guid.present?
    return internal_error_status unless group_data.present? || group_guid.present?

    group = new(target: target, mapper: mapper, group_data: group_data).
      find_group(
        group_guid: group_guid, exclude_members: exclude_members
      )

    return group_not_found_error_status if group.nil?
    success_group_status(group)
  end

  # Public: Provisions a group under the target.
  #
  # target          - The target the group is under. Currently Business and Organization
  #                   objects can be targeted.
  # group_data      - The Platform::Provisioning::SCIMGroupData with all of the
  #                   IdP provided data about the group.
  # mapper          - The provisioning mapper responsible for mapping the
  #                   provided group_data to an external group. This is
  #                   specific for the provisioning scheme (e.g. SAML vs SCIM).
  #
  # Returns Result record
  def self.provision(
    target:,
    group_data:,
    mapper:
  )
    return internal_error_status \
      unless target.present? && target.external_provider.present? && mapper.present? && group_data.present?

    new(target: target, mapper: mapper, group_data: group_data).
      provision_group
  end

  # Public: Updates a group under the target
  #
  # target          - The target the group is under. Currently Business and Organization
  #                   objects can be targeted.
  # group_data      - The Platform::Provisioning::SCIMGroupData with all of the
  #                   IdP provided data about the group.
  # mapper          - The provisioning mapper responsible for mapping the
  #                   provided group_data to an external group. This is
  #                   specific for the provisioning scheme (e.g. SAML vs SCIM).
  # group_guid      - (optional) The GUID of the external group to
  #                   update.
  # group           - (optional) an external group record
  #
  # Returns Result record
  def self.update(
    target:,
    group_data:,
    mapper:,
    group_guid: nil,
    group: nil
  )
    return internal_error_status \
      unless target.present? && target.external_provider.present? && mapper.present? && group_data.present?

    new(target: target, mapper: mapper, group_data: group_data).
      update_group(
        group_guid: group_guid,
        group: group
      )
  end

  # Public: Updates or provisions a group under the target
  #
  # target          - The target the group is under. Currently Business and Organization
  #                   objects can be targeted.
  # group_data      - The Platform::Provisioning::SCIMGroupData with all of the
  #                   IdP provided data about the group.
  # mapper          - The provisioning mapper responsible for mapping the
  #                   provided group_data to an external group. This is
  #                   specific for the provisioning scheme (e.g. SAML vs SCIM).
  #
  # Returns Result record
  def self.provision_or_update(
    target:,
    group_data:,
    mapper:
  )
    return internal_error_status \
      unless target.present? && target.external_provider.present? && mapper.present? && group_data.present?

    new(target: target, mapper: mapper, group_data: group_data).
      provision_or_update_group
  end

  # Public: De-provisions a group and removes group from the enterprise.
  #
  # target          - The target the group is under. Currently Business and Organization
  #                   objects can be targeted.
  # group_data      - The Platform::Provisioning::SCIMGroupData with all of the
  #                   IdP provided data about the group.
  # mapper          - The provisioning mapper responsible for mapping the
  #                   provided group_data to an external group. This is
  #                   specific for the provisioning scheme (e.g. SAML vs SCIM).
  # group_guid      - (optional) The GUID of the external identity to
  #                   provision. If not specified, the mapper will be used
  #                   to find or build one.
  # group          - (optional) an external group record
  #
  # Returns Result record
  def self.deprovision(
    target:,
    group_data:,
    mapper:,
    group_guid: nil,
    group: nil
  )
    return internal_error_status \
      unless target.present? && target.external_provider.present? && mapper.present? && group_data.present?

    new(target: target, mapper: mapper, group_data: group_data).
      deprovision_group(
        group_guid: group_guid,
        group: group,
      )
  end

  # define attribute readers for the instance
  attr_reader :target, :group_data, :mapper

  # Initialize an instance of a class
  #
  # target          - The target the group is under. Currently Business and Organization
  #                   objects can be targeted.
  # group_data       - The Platform::Provisioning::SCIMGroupData with all of the
  #                   IdP provided data about the user.  TODO: Create a mapped group data
  #                   specific for the provisioning scheme (e.g. SAML vs SCIM).
  # mapper          - The provisioning mapper responsible for mapping the
  #                   provided group_data to an external group.
  def initialize(target:, group_data:, mapper:)
    @target = target
    @group_data = group_data
    @mapper = mapper
  end

  # Note the methods below are override points for subclasses
  # they will not change the interface, but can provide a different
  # way of processing data for each provisioner

  # Public: This method returns all groups for a given mapper type
  #
  # Returns an Array of ExternalGroup
  def find_all_groups
    target.external_provider.external_groups.not_deleted
  end

  # Public: This method performs a find of a single group, it can search by an
  #   group guid or mapper and group data
  #
  # Returns ExternalGroup instance of nil
  def find_group(group_guid: nil, filter_deleted: true, exclude_members: true)
    if group_guid.present?
      query = target.external_provider
        .external_groups

      if filter_deleted
        query = query.not_deleted
      end

      unless exclude_members
        query = if GitHub.enterprise?
          query.with_scim_preloads
        else
          query.with_scim_preloads_emu
        end
      end

      query.find_by_guid(group_guid)
    else
      mapper.find_group(target: target, group_data: group_data, filter_deleted: filter_deleted) unless group_data.nil?
    end
  end

  # Public: Provisions a new group
  #
  # Returns Result record
  def provision_group
    # check if the group has not been provisioned already
    # we do not want to filter deleted groups since the group
    # can be re-added on the IdP side which we soft deleted
    # in those cases we want to un-delete the group
    group = find_group(filter_deleted: false)

    # If the group was found and it is marked as deleted, restore it and run an update
    if group&.deleted_at.present?
      group.restore_group
      return update_group(group_guid: group.guid, group: group)
    end

    return self.class.duplicate_group_found unless group.nil?

    # create new group record and check for provisioning
    group = mapper.build_group(target: target)
    return self.class.provisioning_not_enabled(mapper.provisioning_not_enabled) if group.nil?

    result = save_provisioned_group(group)
    return result unless result.success?

    perform_external_group_member_reconcile_job(group)

    result
  end

  # Public: Updates a group
  #
  # group_guid      - (optional) The GUID of the external group to
  #                   update.
  # group           - (optional) an external group record
  #
  # Returns Result record
  def update_group(
    group_guid:,
    group:
  )
    # if external identity was not provided
    if group.nil?
      group = find_group(group_guid: group_guid, exclude_members: !group_data.replace_all_members?)
      return self.class.group_not_found_error_status if group.nil?
    end

    if group_data.replace_all_members?
      result = reconcile_members(group)
      return result unless result.success?
    else
      result = preprocess_group_members(group)
      return result unless result.success?
    end

    result = save_updated_group(group)
    return result unless result.success?

    perform_external_group_member_reconcile_job(group)

    result
  end

  # Public: Updates or provisions a group under the target.
  #
  # Returns Result record
  def provision_or_update_group
    group = find_group

    # Provision group if it was not found
    if group.nil?
      provision_group
    else
      update_group(
        group_guid: nil,
        group: group,
      )
    end
  end

  # Public: De-provisions a group and removes user from the enterprise.
  #
  # actor_id        - Id of the actor making the deprovision request
  # group_guid      - (optional) The GUID of the external group to
  #                   deprovision.
  # group           - (optional) an external group record
  #
  # Returns Result record
  def deprovision_group(
    group_guid:,
    group:
  )
    # if external group was not provided
    if group.nil?
      group = find_group(group_guid: group_guid, filter_deleted: false)
      return self.class.group_not_found_error_status if group.nil?
    end

    return self.class.success_group_status(group) if group.deleted_at.present?

    save_deprovisioned_group(group)
  end

  # all of the protected methods can be overwritten
  protected

  # Protected: method to process group memberships.  It opens a transaction and creates all members within the same transaction
  #
  # Returns Result object
  def process_group_memberships_bulk(group)
    if @destroy_array&.any? || @create_hash&.any?
      result  = nil

      ExternalIdentityGroupMembership.transaction(requires_new: true) do
        begin
          # delete all of the membership records all at once
          bulk_delete_memberships(group, @destroy_array) if @destroy_array&.any?

          # create all of the membership records all at once
          bulk_create_memberships(group, @create_hash) if @create_hash&.any?
        rescue ActiveRecord::RecordInvalid => e
          result = Platform::Provisioning::Result.new \
            errors: Platform::Provisioning::Error.invalid_group(message: e.record.errors.first)

          # rollback the transaction, something went wrong on the database level
          raise ActiveRecord::Rollback
        end
      end

      if enterprise_teams_enabled?(target)
        group.enterprise_teams.each do |team|
          team.instrument_update
        end
      end

      return result if result && !result.success?
    end

    self.class.success_group_status(group)
  end

  def perform_external_group_member_reconcile_job(group)
    @destroy_array&.each do |id|
      ExternalGroupMemberReconcileJob.perform_later(external_identity_id: id, external_group_id: group.id, caller: self.class.name, operation: :remove_member)
    end

    @create_hash&.keys&.each do |id|
      ExternalGroupMemberReconcileJob.perform_later(external_identity_id: id, external_group_id: group.id, caller: self.class.name, operation: :add_member)
    end
  end

  # Private: Create records using a bulk create operation
  #
  # Returns Result object
  def bulk_create_memberships(group, create_hash)
    existing_records = group
      .external_identity_group_memberships
      .where(external_identity_id: create_hash.keys)
      .pluck(:external_identity_id)

    # remove duplicate records before adding, just in case
    # record is sent multiple times
    create_hash.delete_if { |key, _value| existing_records.include?(key) }

    # create all of the membership records at the same statement
    unless create_hash.empty?
      create_hash.values.each_slice(200) { |batch| ExternalIdentityGroupMembership.insert_all(batch) }
    end
  end

  # Private: Deletes records using a bulk delete_all operation
  #
  # Returns Result object
  def bulk_delete_memberships(group, destroy_array)
    # delete all of the membership records all at once
    # it is safe to use delete_all since there are not triggers in the model
    group.external_identity_group_memberships.where(external_identity_id: destroy_array).in_batches(of: 200).delete_all
  end

  # Protected: Create external group new member hash to be run later
  #
  # adds records to create_hash object
  #
  # Returns Result object
  def create_new_member_hash(
    group:,
    identity_guid:,
    external_identities:
  )
    identity = external_identities[identity_guid]
    return self.class.identity_not_found_error_status if identity.nil?
    return Platform::Provisioning::Result.new \
      errors: Platform::Provisioning::Error.add_member(
        message: MEMBER_DELETED,
      ) if identity[:deleted_at].present?

    @create_hash[identity[:id]] = { external_group_id: group.id, external_identity_id: identity[:id] } if @create_hash[identity[:id]].nil?

    self.class.success_group_status(group)
  end

  # Protected: Pushes the identity id to destroy array if applicable
  #
  # Returns Result object
  def push_identity_to_destroy_array(
    group:,
    identity_guid:,
    external_identities:
  )
    # query deleted identities also
    identity = external_identities[identity_guid]
    # return success if the identity does not exist
    return if identity.nil?

    @destroy_array.push(identity[:id])
  end

  # Protected: This method will reconcile all of the members when replace operation was execute
  #     on members
  #
  # Returns ScimGroupData
  def reconcile_members(group)
    @destroy_array = []
    @create_hash = {}

    new_members = group_data.members.to_h { |item| [item["value"], true] }
    group_data.delete_all("members")

    group.external_identity_group_memberships.joins(:external_identity).pluck(:external_identity_id, :guid).each do |id, guid|
      # member does not exist in the new members list, add it to the delete list
      @destroy_array.push(id) if new_members.delete(guid).nil?
    end

    # members to add
    external_identities = ExternalIdentity.by_provider(target.external_provider)
      .where(guid: new_members.keys)
      .pluck(:guid, :id, :deleted_at)
      .to_h { |guid, id, deleted_at| [guid, { id: id, deleted_at: deleted_at }] }

    # Will rollback all the post if any of the members fail
    new_members.keys.each do |guid|
      # Add member, member is added to create_hash, for later bulk insert
      result = create_new_member_hash(
        group: group,
        identity_guid: guid,
        external_identities: external_identities,
      )

      return result if result && !result.success?
    end

    self.class.success_group_status(group_data)
  end

  # hooks for before and after methods

  # Protected: A hook trigger method that will be executed before provisioned group is saved
  #
  # Returns Result object
  def before_provision_group(group)
    # set the audit operation
    @operation = push_to_context(operation: PROVISION)

    # set the appropriate data in the external group record
    # needs to be done before the context is set
    mapper.set_group_data(group: group, group_data: group_data)

    self.class.success_group_status(group)
  end

  # Protected: A hook trigger method that will be executed after provisioned group is saved
  #
  # Returns Result object
  def after_provision_group(group)
    # provision a new group with members, should not really happen
    # since both Azure and Okta are sending posts without members
    # members are added during patch operations, it is here just in case
    # some other IdP sends members with a post.
    # In case the members are passed in during provisioning we need to process them
    # Since we did not have the group id outside of the transaction processing needs to be done here
    # This is just a precautionary measure since members are not usually passed in during provisioning
    result = preprocess_group_members(group)
    return result unless result.success?

    result = process_group_memberships_bulk(group)
    return result unless result.success?

    self.class.success_group_status(group)
  end

  # Protected: A hook trigger method that will be executed before updated group is saved
  #
  # Returns Result object
  def before_update_group(group)
    # set the audit operation
    @operation = push_to_context(operation: UPDATE)

    # set the appropriate data in the external group record
    # needs to be done before the context is set
    mapper.set_group_data(group: group, group_data: group_data)

    self.class.success_group_status(group)
  end

  # Protected: A hook trigger method that will be executed after updated group is saved
  #
  # Returns Result object
  def after_update_group(group)
    # delete none existing memberships and add new once
    # for added members create memberships through teams if the group has been added
    # for the deleted members remove memberships through teams
    result = process_group_memberships_bulk(group)
    return result unless result.success?

    self.class.success_group_status(group)
  end

  # Protected: A hook trigger method that will be executed before deprovisioned group is saved
  #
  # Returns Result object
  def before_deprovision_group(group)
    @operation = push_to_context(operation: DELETE)

    result = group.mark_group_deleted
    return self.class.internal_error_status unless result

    self.class.success_group_status(group)
  end

  # Protected: A hook trigger method that will be executed after deprovisioned group is saved
  #
  # Returns Result object
  def after_deprovision_group(group)
    self.class.success_group_status(group)
  end

  # Protected: Push operation to context
  #
  # operation        - an operation to setup in an auditing context
  #
  # Returns operation pushed
  def push_to_context(operation:)
    # Audit log data
    GitHub.context.push operation: operation
    Audit.context.push operation: operation

    operation
  end

  private

  # Private: This method will process the group memberships
  #
  # Returns nothing
  def preprocess_group_members(group)
    # Pre-process the group data to remove any memberships that are not in the group_data
    # This is done here to avoid spending extra time in the transaction
    if group_data.members && !group_data.members.empty?
      @destroy_array = []
      @create_hash = {}

      identity_guids = group_data.members.map { |member| member["value"] }
      return self.class.bad_request_status if identity_guids.any? { |guid| !guid.is_a?(String) }

      # Select all of the external identity records to be inserted or deleted
      # in a single select
      external_identities = ExternalIdentity.by_provider(target.external_provider)
        .where(guid: identity_guids)
        .pluck(:guid, :id, :deleted_at)
        .to_h { |guid, id, deleted_at| [guid, { id: id, deleted_at: deleted_at }] }

      # Will rollback all the post if any of the members fail
      group_data.members.each do |member|
        # Create or delete members, if no operation is specified assumes an add
        operation = :add
        operation = member["metadata"][:operation] if member["metadata"].present?

        if operation == :add
          # Add member, member is added to create_hash, for later bulk insert
          result = create_new_member_hash(
            group: group,
            identity_guid: member["value"],
            external_identities: external_identities,
          )
        else
          # Add member to destroy_array, for later deletion
          push_identity_to_destroy_array(
            group: group,
            identity_guid: member["value"],
            external_identities: external_identities,
          )
        end

        return result if result && !result.success?
      end
    end

    self.class.success_group_status(group)
  end

  # Private: A method to execute save for provisioned group.
  #       Hiding the implementation from the user.
  #
  # Returns Result object
  def save_provisioned_group(group)
    execute_save_group(
      group: group,
      before_save: -> (in_group) { before_provision_group(in_group) },
      after_save: -> (in_group) { after_provision_group(in_group) }
    )
  end

  # Private: A method to execute save for updated group.
  #       Hiding the implementation from the user.
  #
  # Returns Result object
  def save_updated_group(group)
    execute_save_group(
      group: group,
      before_save: -> (in_group) { before_update_group(in_group) },
      after_save: -> (in_group) { after_update_group(in_group) }
    )
  end

  # Private: A method to execute save for deprovisioned group.
  #       Hiding the implementation from the user.
  #
  # Returns Result object
  def save_deprovisioned_group(group)
    execute_save_group(
      group: group,
      before_save: -> (in_group) { before_deprovision_group(in_group) },
      after_save: -> (in_group) { after_deprovision_group(in_group) }
    )
  end

  # Private: Saves group and execute before and after save trigger hook methods.
  #
  # group           - The group to update
  # before_save     - A lambda passing in a method to execute before the group is saved
  # after_save      - A lambda passing in a method to execute after the group is saved
  #
  # Returns Result record
  def execute_save_group(
    group:,
    before_save:,
    after_save:
  )
    set_context

    result = nil

    # Checks if there is a displayName attribute update linked to the external_group to instrument a `update_display_name` action if there are updates to be made.
    updated_display_name_data = group_data.display_name
    is_same_display_name = updated_display_name_data ? group.display_name == updated_display_name_data : nil

    ExternalGroup.transaction do
      result = before_save.call(group)
      self.class.rollback_unless_success(result)

      result = save_group(group)
      self.class.rollback_unless_success(result)

      result = after_save.call(group)
      self.class.rollback_unless_success(result)

      group.instrument_event(@operation)

      if is_same_display_name == false
        group.instrument_event(:update_display_name)
      end
    end

    result
  end

  # Private: Save current group record and process errors if any
  #
  # group        - The group to update
  #
  # Returns Result object
  def save_group(
    group
  )
    if group.save
      self.class.success_group_status(group)
    else
      # there was an issue saving the identity
      messages = group.errors.full_messages

      Platform::Provisioning::Result.new \
        errors: messages.map { |m| Platform::Provisioning::Error.invalid_group(message: m) }
    end
  end

  # Private: Set the current context for logging purposes
  #
  # identity        - an external identity record to set
  # user_id         - a user id this context is tied to
  #
  # Returns nothing
  def set_context
    context = {
      identity_mapper: mapper.to_s,
      target: target,
    }

    # Audit log data
    GitHub.context.push context
    Audit.context.push context
  end
end
