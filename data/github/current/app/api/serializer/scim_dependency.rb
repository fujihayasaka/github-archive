# typed: false
# frozen_string_literal: true

module Api::Serializer::ScimDependency

  # Creates a SCIM error hash to be serialized to JSON.
  #
  # error - A SCIM::ErrorResponse instance.
  #
  # Returns a Hash.
  def scim_error_hash(error, options = {})
    {
      schemas: [SCIM::ERROR_SCHEMA],
      status: error.status,
      scimType: error.scim_type,
      detail: error.detail,
    }
  end

  # Creates a Hash to be serialized to JSON.
  #
  # identity - ExternalIdentity instance.
  #
  # Returns a Hash if the ExternalIdentity exists, or nil.
  def scim_identity_hash(identity, options = {})
    return nil if !identity

    scim_data = identity.scim_user_data

    attributes = identity_attributes_hash(
      identity,
      url_path: "/scim/v2/organizations/#{ identity.target.login_for_api(use: options[:serialize_login]) }/Users/#{ identity.guid }",
      is_active: !identity.destroyed?,
    )

    scim_data.as_json(skip_groups: true).merge(attributes).as_json
  end

  # Creates a Hash for an enterprise identity to be serialized to JSON.
  #
  # identity - ExternalIdentity instance.
  #
  # Returns a Hash if the ExternalIdentity exists, or nil.
  def enterprise_scim_identity_hash(identity, options = {})
    return nil unless identity

    scim_data = identity.scim_user_data

    # Do not only use scim_data.active? to check if the user is active, since it
    # returns true when the the active flag is missing in the attributes and since
    # we delete all attributes when the user is disabled or deleted, we need to check if the
    # user is disabled or deleted in external identities as well as the flag.
    attributes = identity_attributes_hash(
      identity,
      url_path: "/scim/v2#{enterprise_slug(identity.target)}/Users/#{ identity.guid }",
      is_active: !identity.destroyed? && !identity.disabled_at? && !identity.deleted_at? && scim_data.active?,
    )

    if Platform::Provisioning::GroupsUserDataWrapper.new(scim_data).groups_attributes.any?
      attributes[:groups] = scim_groups_array(
        Platform::Provisioning::GroupsUserDataWrapper.new(scim_data).groups_attributes
      )
    else
      excluded_attributes = excluded_attributes(options)
      unless excluded_attributes.include?(:groups)
        attributes[:groups] = enterprise_scim_user_group_array(identity)
      end
    end

    scim_data.as_json(skip_groups: true).merge(attributes).as_json
  end

  # Creates a Hash for a SCIM group.
  #
  # identity - ExternalIdentity instance.
  # options  - Hash of options. Supported options include:
  #            - :excluded_attributes - String of comma-separated values
  #              representing the names of attributes that should be excluded
  #              in the returned Hash.
  #
  # Returns a Hash if the ExternalIdentity exists, or nil.
  def enterprise_group_hash(identity, options = {})
    return nil unless identity

    scim_data = identity.scim_group_data

    result = {
      schemas: [SCIM::GROUP_SCHEMA],
      id: identity.guid,
      externalId: scim_data.external_id,
      displayName: scim_data.display_name,
      members: enterprise_scim_member_array(identity),
      meta: {
        resourceType: "Group",
        created: identity.created_at,
        lastModified: identity.updated_at,
        location: url("/scim/v2#{enterprise_slug(identity.target)}}/Groups/#{ identity.guid }"),
      }
    }

    # Filter the response if the :excluded_attributes option is provided
    filter_attributes(result, options)
  end

  # Creates a Hash for a SCIM group from an external group
  #
  # external_group - ExternalGroup instance.
  # options  - Hash of options. Supported options include:
  #            - :excluded_attributes - String of comma-separated values
  #              representing the names of attributes that should be excluded
  #              in the returned Hash.
  #
  # Returns a Hash if the ExternalGroup exists, or nil.
  def enterprise_scim_group_hash(external_group, options = {})
    return nil unless external_group

    result = {
      schemas: [SCIM::GROUP_SCHEMA],
      id: external_group.guid,
      externalId: external_group.external_id,
      displayName: external_group.display_name,
      meta: {
        resourceType: "Group",
        created: external_group.created_at,
        lastModified: external_group.updated_at,
        location: url("/scim/v2#{enterprise_slug(external_group.target)}/Groups/#{ external_group.guid }"),
      }
    }

    result[:members] = []

    # try not creating members attributes if they are excluded
    excluded_attributes = excluded_attributes(options)
    unless excluded_attributes.include?(:members) || external_group.external_identity_group_memberships.empty?
      result[:members] = enterprise_group_member_array(external_group)
    end

    # Filter the response if the :excluded_attributes option is provided
    filter_attributes(result, options)
  end

  # Private: Get excluded attributes from options
  #
  # options  - Hash of options. Supported options include:
  #            - :excluded_attributes - String of comma-separated values
  #              representing the names of attributes that should be excluded
  #              in the returned Hash.
  #
  # Returns an array of excluded attributes
  def excluded_attributes(options)
    if options.present? && options[:excluded_attributes].present?
      return options[:excluded_attributes].split(",").map do |attr|
        attr = attr.strip.to_sym
        # Never let the :schemas or :id attributes be excluded
        next if attr == :schemas || attr == :id
        attr
      end.compact
    end

    []
  end

  # Private: Filters attributes when excluded_attributes where provided
  #
  # result_hash - a result hash to filter
  # options  - Hash of options. Supported options include:
  #            - :excluded_attributes - String of comma-separated values
  #              representing the names of attributes that should be excluded
  #              in the returned Hash.
  #
  # Returns a hash
  def filter_attributes(result_hash, options)
    if options.present? && options[:excluded_attributes].present?
      excluded_attributes = excluded_attributes(options)

      excluded_attributes.each do |attr|
        result_hash.delete(attr)
      end
    end

    result_hash
  end

  def enterprise_scim_user_group_array(identity)
    external_group_ids = identity.external_identity_group_memberships.pluck(:external_group_id)
    external_groups = ExternalGroup.where(id: external_group_ids)
    external_groups.map do |group|
      {
        :value => group.guid,
        :$ref => url("/scim/v2#{enterprise_slug(identity.target)}/Groups/#{ group.guid }"),
        :display => group.display_name,
      }
    end
  end

  def enterprise_group_member_array(external_group)
    members = external_group.external_identity_group_memberships.map(&:external_identity).reject(&:disabled_at?)

    ref_prefix = "/scim/v2#{enterprise_slug(external_group.target)}/Users/"

    members.map do |user_identity|
      if GitHub.enterprise?
        {
          :value => user_identity.guid,
          :$ref => url("#{ref_prefix}#{user_identity.guid}"),
          :display => user_identity.display_name,
        }
      else
        {
          :value => user_identity.guid,
          :$ref => url("#{ref_prefix}#{user_identity.guid}"),
          :display => user_identity.user.profile.name,
        }
      end
    end
  end

  def enterprise_scim_member_array(identity)
    members = identity.prefilled_group_members

    members.map do |user_identity|
      {
        :value => user_identity.guid,
        :$ref => url("/scim/v2#{enterprise_slug(identity.target)}/Users/#{ user_identity.guid }"),
        :display => (user_identity.display_name || user_identity.saml_user_data.name_id).to_s,
      }
    end
  end

  def enterprise_groups_hash(identities, options = {})
    scim_list_hash(identities) do |resource|
      enterprise_group_hash(resource, options)
    end
  end

  def scim_identities_hash(results, options = {})
    scim_list_hash(results) do |resource|
      scim_identity_hash(resource)
    end
  end

  def enterprise_scim_identities_hash(results, options = {})
    scim_list_hash(results) do |resource|
      enterprise_scim_identity_hash(resource)
    end
  end

  def enterprise_scim_groups_hash(external_groups, options = {})
    scim_list_hash(external_groups) do |resource|
      enterprise_scim_group_hash(resource, options)
    end
  end

  private

  # Private: Returns correct portion of the URL for SCIM location based on the environment
  #
  # Returns String
  def enterprise_slug(target)
    if target.is_a?(Business) && target.enterprise_server_scim_enabled?
      ""
    else
      "/enterprises/#{target.slug}"
    end
  end

  def identity_attributes_hash(identity, url_path:, is_active:)
    {
      schemas: [SCIM::USER_SCHEMA],
      id: identity.guid,
      active: is_active,
      meta: {
        resourceType: "User",
        created: identity.created_at,
        lastModified: identity.updated_at,
        location: url(url_path),
      },
    }
  end

  # Internal: Transforms the Array of groups as stored internally separated into
  # a SCIM-compliant structure
  def scim_groups_array(groups)
    groups.map do |group|
      group.slice(:value)
    end
  end

  # Internal: generates a SCIM list type result with pagination
  def scim_list_hash(results)
    {
      schemas: [SCIM::LIST_SCHEMA],
      totalResults: results.total_results,
      itemsPerPage: results.items_per_page,
      startIndex: results.start_index,
      Resources: results.resources.map do |resource|
        yield(resource)
      end,
    }
  end
end
