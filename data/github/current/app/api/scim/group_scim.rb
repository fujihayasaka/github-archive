# typed: false
# frozen_string_literal: true

# Group SCIM api class implements endpoint methods used in the scim groups endpoint
class Api::SCIM::GroupSCIM < Api::SCIM::BaseSCIM

  attr_reader :provisioner

  SERIALIZE_METHOD = :enterprise_scim_group_hash
  JSON_RESOURCE = "scim-group"
  MEMBERS = "members"

  # Public: Implementation of a GET Groups endpoint
  #
  # target           - target the the execution runs under, could be an organization or an enterprise
  # serialize_method - method used to serialize the returned results to json (can be setup in an override)
  # json_resource    - a resource name for extracting json (can be setup in an override)
  #
  # Returns Result object that can either contain an error or a collection of external groups
  def get_groups(target:, serialize_method: nil, json_resource: nil)
    execute(
      method: :get_groups_internal,
      target: target,
      serialize_method: serialize_method || :enterprise_scim_groups_hash,
      json_resource: json_resource
    )
  end

  # Public: Implementation of GET specific Groups endpoint
  #
  # target           - target the the execution runs under, could be an organization or an enterprise
  # serialize_method - method used to serialize the returned results to json (can be setup in an override)
  # json_resource    - a resource name for extracting json (can be setup in an override)
  #
  # Returns Result object that can either contain an error or an external group
  def get_group(target:, serialize_method: nil, json_resource: nil)
    execute(
      method: :get_group_internal,
      target: target,
      serialize_method: serialize_method,
      json_resource: json_resource
    )
  end

  # Public: Implementation of a POST Groups endpoint
  #
  # target           - target the the execution runs under, could be an organization or an enterprise
  # serialize_method - method used to serialize the returned results to json (can be setup in an override)
  # json_resource    - a resource name for extracting json (can be setup in an override)
  #
  # Returns Result object that can either contain an error or a newly created external group
  def provision_group(target:, serialize_method: nil, json_resource: nil)
    execute(
      method: :provision_group_internal,
      target: target,
      serialize_method: serialize_method,
      json_resource: json_resource
    )
  end

  # Public: Implementation of a PUT Groups endpoint, put replaces all of the scim group data values
  #
  # target           - target the the execution runs under, could be an organization or an enterprise
  # serialize_method - method used to serialize the returned results to json (can be setup in an override)
  # json_resource    - a resource name for extracting json (can be setup in an override)
  #
  # Returns Result object that can either contain an error or a updated external group
  def update_group(target:, serialize_method: nil, json_resource: nil)
    execute(
      method: :update_group_internal,
      target: target,
      serialize_method: serialize_method,
      json_resource: json_resource
    )
  end

  # Public: Implementation of a PATCH Groups endpoint, patch replaces only certain attributes in scim group data
  #
  # target           - target the the execution runs under, could be an organization or an enterprise
  # serialize_method - method used to serialize the returned results to json (can be setup in an override)
  # json_resource    - a resource name for extracting json (can be setup in an override)
  #
  # Returns Result object that can either contain an error or a updated external group
  def patch_group(target:, serialize_method: nil, json_resource: nil)
    execute(
      method: :patch_group_internal,
      target: target,
      serialize_method: serialize_method,
      json_resource: json_resource
    )
  end

  # Public: Implementation of a DELETE Groups endpoint
  #
  # target           - target the the execution runs under, could be an organization or an enterprise
  # serialize_method - method used to serialize the returned results to json (can be setup in an override)
  # json_resource    - a resource name for extracting json (can be setup in an override)
  #
  # Returns Result object that can either contain an error or an empty result with status code of 204
  def delete_group(target:, serialize_method: nil, json_resource: nil)
    execute(
      method: :delete_group_internal,
      target: target,
      serialize_method: serialize_method,
      json_resource: json_resource
    )
  end

  # Public: The method that sets the provisioner, it is called in the execute
  #
  # target           - target the the execution runs under, could be an organization or an enterprise,
  #                    provisioner can be selected based on that target
  #
  # Returns nothing
  def set_provisioner(target)
    @provisioner = if target.enterprise_server_scim_enabled?
      Platform::Provisioning::EnterpriseServerSCIMGroupProvisioner
    elsif target.is_a?(Business) && target.enterprise_managed_user_enabled?
      Platform::Provisioning::EnterpriseManagedGroupProvisioner
    else
      Platform::Provisioning::BaseGroupProvisioner
    end
  end

  # Public: A override of a main execution method. It add the
  #
  # method           - the name of the method to execute implemented in the endpoint module
  # target           - target the the execution runs under, could be an organization or an enterprise
  # serialize_method - method used to serialize the returned results to json (can be setup in an override)
  # json_resource    - a resource name for extracting json (can be setup in an override)
  #
  # Returns scim result
  def execute(method:, target:, serialize_method: nil, json_resource: nil)
    set_provisioner(target)
    super
  end

  protected

  # Protected: Delivers a 404 error when SCIM is not supported on an enterprise
  #
  # enterprise          - Enterprise where SAML is enabled
  #
  # Returns 404 error or nothing
  def enterprise_scim_enabled(enterprise, status: 404)
    if enterprise.enterprise_managed_user_enabled?
      deliver_error!(status, message: "This Enterprise account does not support group provisioning.") unless enterprise_scim_enabled?(enterprise)
    elsif GitHub.enterprise?
      deliver_error!(status, message: "This Enterprise Server does not support group provisioning.") unless enterprise_scim_enabled?(enterprise)
    else
      unless GitHub.flipper[:enterprise_idp_provisioning].enabled?(enterprise)
        deliver_error!(404) if status == 404
        deliver_error!(400, message: "This Enterprise account does not support membership provisioning.") if status == 400
      end
    end
  end

  private

  # Private: Internal implementation of a GET Groups endpoint
  #
  # Returns Result object that can either contain an error or a collection of external groups
  def get_groups_internal
    # Call a provisioner query all available groups
    result = provisioner.find_all(target: @call_options[:target])

    if result.success?
      groups = if params[:excludedAttributes].present? && params[:excludedAttributes].include?(MEMBERS)
        result.external_group
      else
        if GitHub.enterprise?
          result.external_group.with_scim_preloads
        else
          result.external_group.with_scim_preloads_emu
        end
      end
    else
      return GitHub::SCIM::Result.deliver_error(500, "Failed to get groups")
    end

    # check if any filters where passed in as parameters to the endpoint
    if params[:filter]
      groups = begin
        groups.scim_filter(params[:filter])
      rescue SCIM::Filter::InvalidFilterError => e
        # https://tools.ietf.org/html/rfc7644#section-3.12
        return GitHub::SCIM::Result.deliver_scim_error(400, scim_type: "invalidFilter", detail: e.message)
      end
    end

    # create a paginated collection of groups
    results = paginated_results(groups.order(:id))

    # return success with a collection of groups
    GitHub::SCIM::Result.deliver_scim(@call_options[:serialize_method], results, 200,
      excluded_attributes: params[:excludedAttributes])
  end

  # Private: Internal implementation of GET specific Group endpoint
  #
  # Returns Result object that can either contain an error or an external group
  def get_group_internal
    # Call a provisioner to find a specific group based on the guid passed in
    result = provisioner.find(
      target: @call_options[:target],
      group_guid: params[:external_identity_guid],
      exclude_members: params[:excludedAttributes].present? && params[:excludedAttributes].include?(MEMBERS)
    )

    # Log the external_id to splunk
    if (log_data = request.env[Rack::RequestLogger::APPLICATION_LOG_DATA])
      log_data["gh.external_identities.external_id"] = result&.external_group&.external_id
    end

    if result.success?
      # return success with an group object
      GitHub::SCIM::Result.deliver_scim(@call_options[:serialize_method], result.external_group, 200,
        excluded_attributes: params[:excludedAttributes])
    else
      GitHub::SCIM::Result.deliver_scim_error(404, detail: "Resource #{ params[:external_identity_guid] } not found.")
    end
  end

  # Private: Internal implementation of a POST Groups endpoint
  #
  # Returns Result object that can either contain an error or a newly created external group
  def provision_group_internal
    # get the json from a post and convert it to group data
    json = receive_with_schema(@call_options[:json_resource], "create")
    group_data = Platform::Provisioning::SCIMGroupData.load(json)

    # Log the external_id to splunk
    if (log_data = request.env[Rack::RequestLogger::APPLICATION_LOG_DATA])
      log_data["gh.external_identities.external_id"] = json["externalId"]
    end

    # call provisioner provision method
    result = provisioner.provision(
      target: @call_options[:target],
      group_data: group_data,
      mapper: Platform::Provisioning::SCIMGroupMapper,
    )

    # check if provisioning returned a successful result and return identity, otherwise process result error
    if result.success?
      GitHub::SCIM::Result.deliver_scim(@call_options[:serialize_method], result.external_group, 201)
    else
      deliver_result_error(result)
    end
  end

  # Private: Internal implementation of a PUT Groups endpoint, put replaces all of the scim group data values
  #
  # Returns Result object that can either contain an error or a updated external group
  def update_group_internal
    # Find the external group by a guid
    result = provisioner.find(
      target: @call_options[:target],
      group_guid: params[:external_identity_guid],
      exclude_members: false
    )

    # Log the external_id to splunk
    if (log_data = request.env[Rack::RequestLogger::APPLICATION_LOG_DATA])
      log_data["gh.external_identities.external_id"] = result&.external_group&.external_id
    end

    # check if group was found end return an error
    unless result.success?
      return GitHub::SCIM::Result.deliver_scim_error(404, detail: "Resource #{ params[:external_identity_guid] } not found.")
    end

    # get the json from a put and convert it to group data
    json = receive_with_schema(@call_options[:json_resource], "put")
    group_data = Platform::Provisioning::SCIMGroupData.load(json)

    # Only replace members if they were provided in json
    unless json["members"].nil?
      if process_empty_members(@call_options[:target]) || json["members"].any?
        group_data.replace_all_members(true)
      end
    end

    # call provisioner update method
    result = provisioner.update(
      target: @call_options[:target],
      group_data: group_data,
      mapper: Platform::Provisioning::SCIMGroupMapper,
      group_guid: params[:external_identity_guid],
      group: result.external_group
    )

    # check if update returned a successful result and return identity, otherwise process result error
    if result.success?
      GitHub::SCIM::Result.deliver_scim(@call_options[:serialize_method], result.external_group, 200)
    else
      deliver_result_error(result)
    end
  end

  # Private: Internal implementation of a PATCH Groups endpoint, patch replaces only certain attributes in scim group data
  #
  # Returns Result object that can either contain an error or a updated external group
  def patch_group_internal
    # Find the external group by a guid
    result = provisioner.find(
      target: @call_options[:target],
      group_guid: params[:external_identity_guid]
    )

    # Log the external_id to splunk
    if (log_data = request.env[Rack::RequestLogger::APPLICATION_LOG_DATA])
      log_data["gh.external_identities.external_id"] = result&.external_group&.external_id
    end

    # check if group was found end return an error
    unless result.success?
      return GitHub::SCIM::Result.deliver_scim_error(404, detail: "Resource #{ params[:external_identity_guid] } not found.")
    end

    external_group = result.external_group
    # get existing scim group data
    # operations on members are tagged so we do not need to read all of the members
    group_data = external_group.scim_group_data(include_members: false)

    # get the json from a patch and augment existing user data
    json = receive_with_schema(@call_options[:json_resource], "patch")

    process_result = SCIM::Operation.process_json(group_data, json, target: @call_options[:target])
    unless process_result.success?
      # return error if there was one
      return GitHub::SCIM::Result.deliver_scim_error(process_result.error.status, scim_type: process_result.error.scim_type, detail: process_result.error.detail)
    end

    # call provisioner update method
    result = provisioner.update(
      target: @call_options[:target],
      # operation has user_data
      group_data: process_result.user_data,
      mapper: Platform::Provisioning::SCIMGroupMapper,
      group_guid: params[:external_identity_guid],
      group: external_group
    )

    # check if update returned a successful result and return identity, otherwise process result error
    if result.success?
      # SCIM Groups PATCH endpoint returning 204 is required by Azure SCIM provider. For all other SCIM providers
      # we will return 200 with the updated group.
      if Business.scim_provider_type == :azure_ad
        GitHub::SCIM::Result.deliver_scim(@call_options[:serialize_method], nil, 204)
      else
        GitHub::SCIM::Result.deliver_scim(@call_options[:serialize_method], result.external_group, 200,
          excluded_attributes: MEMBERS)
      end
    else
      deliver_result_error(result)
    end
  end

  # Private: Internal implementation of a DELETE Groups endpoint
  #
  # Returns Result object that can either contain an error or an empty result with status code of 204
  def delete_group_internal
    # Find the external identity by a guid
    result = provisioner.find(
      target: @call_options[:target],
      group_guid: params[:external_identity_guid]
    )

    # Log the external_id to splunk
    if (log_data = request.env[Rack::RequestLogger::APPLICATION_LOG_DATA])
      log_data["gh.external_identities.external_id"] = result&.external_group&.external_id
    end

    # check if group was found end return an error
    unless result.success?
      return GitHub::SCIM::Result.deliver_scim_error(404, detail: "Resource #{ params[:external_identity_guid] } not found.")
    end

    # get existing scim user data and set the active flag to false, which will
    # suspend a user
    group_data = result.external_group.scim_group_data(include_members: false)

    # call provisioner deprovision method
    result = provisioner.deprovision(
      target: @call_options[:target],
      group_data: group_data,
      mapper: Platform::Provisioning::SCIMGroupMapper,
      group_guid: params[:external_identity_guid],
      group: result.external_group
    )

    # check if delete returned a successful result and return empty result, otherwise process result error
    if result.success?
      GitHub::SCIM::Result.deliver_scim(@call_options[:serialize_method], nil, 204)
    else
      deliver_result_error(result)
    end
  end

  # Private: Process scim result, this implementation is called from an execute method in a base
  #      controller processor module.  This implementation is specific to Users endpoint
  #
  # result - a result object to process
  #
  # Returns a payload to be delivered to an IdP
  def process_scim_result(result)
    # if result was a success process it and serialize objects into json
    if result.success?
      # for delete there will be no result, check for it and deliver empty
      if result.results.nil?
        deliver_empty(status: result.status_code)
      else

        # deliver json payload with external identities
        deliver_scim(result.serialize_method, result.results, status: result.status_code,
          excluded_attributes: result.excluded_attributes)
      end
    else
      # deliver appropriate error in the payload
      if result.error_msg.nil?
        # NOTE: deliver_result_error handles reporting internal errors so the result here does not need to be provided
        deliver_scim_error!(result.status_code, scim_type: result.scim_type, detail: result.detail, result: nil)
      else
        deliver_error!(result.status_code, message: result.error_msg)
      end
    end
  end

  # Private: An implementation for checking result object from a provisioner and converting it to an appropriate local
  #   result object
  #
  # result - result object from a provisioner
  #
  # Returns local Result object with appropriate messaged and status codes
  def deliver_result_error(result)
    if result.invalid_identity_error?
      # https://tools.ietf.org/html/rfc7644#section-3.3
      # If the service provider determines that the creation of the requested
      # resource conflicts with existing resources (e.g., a "User" resource
      # with a duplicate "userName"), the service provider MUST return HTTP
      # status code 409 (Conflict) with a "scimType" error code of
      # "uniqueness"
      GitHub::SCIM::Result.deliver_scim_error(409, scim_type: "uniqueness")
    elsif result.forbidden_error?
      GitHub::SCIM::Result.deliver_scim_error(403, detail: result.error_messages.join("\n"))
    else
      # Something unexpected happened. SCIM doesn't define a general error so
      # we'll just respond with an error code from result.
      GitHub.logger.error({
        "exception.type" => result.errors.first.reason,
        "exception.message" => result.error_messages,
        "gh.business.id" => @call_options[:target].id
      })

      # Report internal errors for debugging
      if result&.internal_error?
        Failbot.report!(
          result.errors.get(Platform::Provisioning::Error::INTERNAL_ERROR),
          error_messages: result.error_messages
        )
      end

      GitHub::SCIM::Result.deliver_scim_error(result.error_code, detail: result.error_messages.join("\n"))
    end
  end

  # process_empty_members = true will process the empty group and nuke all the group/team memberships.
  # for AAD, scim/PUT will only update group information, membership is processed in the PATCH call, we will never process AAD membership in PUT call
  def process_empty_members(enterprise)
    return false if enterprise.oidc_enabled?

    Business.scim_provider_type(user_agent: request.user_agent) != :azure_ad
  end
end
