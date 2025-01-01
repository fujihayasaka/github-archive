# typed: false
# frozen_string_literal: true

# User SCIM api class implements endpoint methods used in the scim users endpoint
class Api::SCIM::UserSCIM < Api::SCIM::BaseSCIM
  SERIALIZE_METHOD = :enterprise_scim_identity_hash
  JSON_RESOURCE = "enterprise-scim-user"

  # Public: Implementation of a GET Users endpoint
  #
  # target           - target the the execution runs under, could be an organization or an enterprise
  # serialize_method - method used to serialize the returned results to json (can be setup in an override)
  # json_resource    - a resource name for extracting json (can be setup in an override)
  #
  # Returns Result object that can either contain an error or a collection of external identities
  def get_users(target:, serialize_method: nil, json_resource: nil)
    execute(
      method: :get_users_internal,
      target: target,
      serialize_method: serialize_method || :enterprise_scim_identities_hash,
      json_resource: json_resource
    )
  end

  # Public: Implementation of GET specific Users endpoint
  #
  # target           - target the the execution runs under, could be an organization or an enterprise
  # serialize_method - method used to serialize the returned results to json (can be setup in an override)
  # json_resource    - a resource name for extracting json (can be setup in an override)
  #
  # Returns Result object that can either contain an error or an external identity
  def get_user(target:, serialize_method: nil, json_resource: nil)
    execute(
      method: :get_user_internal,
      target: target,
      serialize_method: serialize_method,
      json_resource: json_resource
    )
  end

  # Public: Implementation of a POST Users endpoint
  #
  # target           - target the the execution runs under, could be an organization or an enterprise
  # serialize_method - method used to serialize the returned results to json (can be setup in an override)
  # json_resource    - a resource name for extracting json (can be setup in an override)
  #
  # Returns Result object that can either contain an error or a newly created external identity
  def provision_user(target:, serialize_method: nil, json_resource: nil)
    execute(
      method: :provision_user_internal,
      target: target,
      serialize_method: serialize_method,
      json_resource: json_resource
    )
  end

  # Public: Implementation of a PUT Users endpoint, put replaces all of the scim user data values
  #
  # target           - target the the execution runs under, could be an organization or an enterprise
  # serialize_method - method used to serialize the returned results to json (can be setup in an override)
  # json_resource    - a resource name for extracting json (can be setup in an override)
  #
  # Returns Result object that can either contain an error or a updated external identity
  def update_user(target:, serialize_method: nil, json_resource: nil)
    execute(
      method: :update_user_internal,
      target: target,
      serialize_method: serialize_method,
      json_resource: json_resource
    )
  end

  # Public: Implementation of a PATCH Users endpoint, patch replaces only certain attributes in scim user data
  #
  # target           - target the the execution runs under, could be an organization or an enterprise
  # serialize_method - method used to serialize the returned results to json (can be setup in an override)
  # json_resource    - a resource name for extracting json (can be setup in an override)
  #
  # Returns Result object that can either contain an error or a updated external identity
  def patch_user(target:, serialize_method: nil, json_resource: nil)
    execute(
      method: :patch_user_internal,
      target: target,
      serialize_method: serialize_method,
      json_resource: json_resource
    )
  end

  # Private: Implementation of a DELETE Users endpoint
  #
  # target           - target the the execution runs under, could be an organization or an enterprise
  # serialize_method - method used to serialize the returned results to json (can be setup in an override)
  # json_resource    - a resource name for extracting json (can be setup in an override)
  #
  # Returns Result object that can either contain an error or an empty result with status code of 204
  def delete_user(target:, serialize_method: nil, json_resource: nil)
    execute(
      method: :delete_user_internal,
      target: target,
      serialize_method: serialize_method,
      json_resource: json_resource
    )
  end

  protected

  # Protected: Delivers a 404 error when SCIM is not supported on an enterprise
  #
  # enterprise          - Enterprise where SAML is enabled
  #
  # Returns 404 error or nothing
  def enterprise_scim_enabled(
    enterprise,
    message: nil
  )
    if enterprise.enterprise_managed_user_enabled?
      deliver_error!(404, message: "This Enterprise account does not support membership provisioning.") unless enterprise_scim_enabled?(enterprise)
    else
      deliver_error!(404, message: message) unless enterprise_scim_enabled?(enterprise)
    end
  end

  private

  # Private: Internal implementation of a GET Users endpoint
  #
  # target           - target the the execution runs under, could be an organization or an enterprise
  # serialize_method - method used to serialize the returned results to json (can be setup in an override)
  # json_resource    - a resource name for extracting json (can be setup in an override)
  #
  # Returns Result object that can either contain an error or a collection of external identities
  def get_users_internal
    result = provisioner.find_all(target: @call_options[:target], mapper: Platform::Provisioning::ScimMapper)

    if result.success?
      identities = result.external_identity
    else
      return GitHub::SCIM::Result.deliver_error(500, "Failed to get users")
    end

    # check if any filters where passed in as parameters to the endpoint
    if params[:filter]
      identities = begin
        identities.scim_filter(params[:filter])
      rescue SCIM::Filter::InvalidFilterError => e
        # https://tools.ietf.org/html/rfc7644#section-3.12
        return GitHub::SCIM::Result.deliver_scim_error(400, scim_type: "invalidFilter", detail: e.message)
      end
    end

    # create a paginated collection of identities
    results = paginated_results(identities.with_scim_managed_preloads)

    # return success with a collection of identities
    GitHub::SCIM::Result.deliver_scim(@call_options[:serialize_method], results, 200)
  end

  # Private: Internal implementation of GET specific Users endpoint
  #
  # Returns Result object that can either contain an error or an external identity
  def get_user_internal
    result = provisioner.find(target: @call_options[:target], identity_guid: params[:external_identity_guid])

    # Log the external_id to splunk
    if (log_data = request.env[Rack::RequestLogger::APPLICATION_LOG_DATA])
      log_data["gh.external_identities.external_id"] = result&.external_identity&.external_id
    end

    if result.success?
      GitHub::SCIM::Result.deliver_scim(@call_options[:serialize_method], result.external_identity, 200)
    else
      GitHub::SCIM::Result.deliver_scim_error(404, detail: "Resource #{ params[:external_identity_guid] } not found.")
    end
  end

  # Private: Internal implementation of a POST Users endpoint
  #
  # Returns Result object that can either contain an error or a newly created external identity
  def provision_user_internal
    # get the json from a post and convert it to user data
    json = receive_with_schema(@call_options[:json_resource], "provision")
    user_data = Platform::Provisioning::ScimUserData.load(json)

    # Log the external_id to splunk
    if (log_data = request.env[Rack::RequestLogger::APPLICATION_LOG_DATA])
      log_data["gh.external_identities.external_id"] = json["externalId"]
    end

    if user_data.nil?
      return GitHub::SCIM::Result.deliver_scim_error(400,
        scim_type: "invalidSyntax",
        detail: "Either \"emails\", \"roles\", or \"groups\" field was supplied in the incorrect format.  Hash is expected with a \"value\" field.")
    end

    if !valid_emails?(user_data)
      return GitHub::SCIM::Result.deliver_scim_error(400,
        scim_type: "invalidSyntax",
        detail: "Email values must be valid email addresses.")
    end

    result = provisioner.provision_or_update \
      target: @call_options[:target],
      user_data: user_data,
      mapper: Platform::Provisioning::ScimMapper,
      inviter_id: current_user.id

    # check if provisioning returned a successful result and return identity, otherwise process result error
    if result.success?
      instrument_emu_onboarding_complete
      GitHub::SCIM::Result.deliver_scim(@call_options[:serialize_method], result.external_identity, 201)
    else
      deliver_result_error(result)
    end
  end

  # Private: Internal implementation of a PUT Users endpoint, put replaces all of the scim user data values
  #
  # Returns Result object that can either contain an error or a updated external identity
  def update_user_internal
    result = provisioner.find(target: @call_options[:target], identity_guid: params[:external_identity_guid])

    # Log the external_id to splunk
    if (log_data = request.env[Rack::RequestLogger::APPLICATION_LOG_DATA])
      log_data["gh.external_identities.external_id"] = result&.external_identity&.external_id
    end

    unless result.success?
      return GitHub::SCIM::Result.deliver_scim_error(404, detail: "Resource #{ params[:external_identity_guid] } not found.")
    end

    # get the json from a put and convert it to user data
    json = receive_with_schema(@call_options[:json_resource], "update")
    user_data = Platform::Provisioning::ScimUserData.load(json)

    if user_data.nil?
      return GitHub::SCIM::Result.deliver_scim_error(400,
        scim_type: "invalidSyntax",
        detail: "Either \"emails\", \"roles\", or \"groups\" field was supplied in the incorrect format.  Hash is expected with a \"value\" field.")
    end

    if !valid_emails?(user_data)
      return GitHub::SCIM::Result.deliver_scim_error(400,
        scim_type: "invalidSyntax",
        detail: "Email values must be valid email addresses.")
    end

    result = provisioner.update \
      target: @call_options[:target],
      user_data: user_data,
      mapper: Platform::Provisioning::ScimMapper,
      identity: result.external_identity,
      actor_id: current_user.id

    # check if update returned a successful result and return identity, otherwise process result error
    if result.success?
      GitHub::SCIM::Result.deliver_scim(@call_options[:serialize_method], result.external_identity, 200)
    else
      deliver_result_error(result)
    end
  end

  # Private: Internal implementation of a PATCH Users endpoint, patch replaces only certain attributes in scim user data
  #
  # Returns Result object that can either contain an error or a updated external identity
  def patch_user_internal
    result = provisioner.find(target: @call_options[:target], identity_guid: params[:external_identity_guid])

    # Log the external_id to splunk
    if (log_data = request.env[Rack::RequestLogger::APPLICATION_LOG_DATA])
      log_data["gh.external_identities.external_id"] = result&.external_identity&.external_id
    end

    unless result.success?
      return GitHub::SCIM::Result.deliver_scim_error(404, detail: "Resource #{ params[:external_identity_guid] } not found.")
    end

    external_identity = result.external_identity
    # get existing scim user data
    user_data = external_identity.scim_user_data

    # get the json from a patch and augment existing user data
    json = receive_with_schema(@call_options[:json_resource], "patch")
    process_result = SCIM::Operation.process_json(user_data, json, target: @call_options[:target])

    unless process_result.success?
      # return error if there was one
      return GitHub::SCIM::Result.deliver_scim_error(process_result.error.status, scim_type: process_result.error.scim_type, detail: process_result.error.detail)
    end

    result = provisioner.update \
      target: @call_options[:target],
      user_data: process_result.user_data,
      mapper: Platform::Provisioning::ScimMapper,
      identity: external_identity,
      actor_id: current_user.id

    # check if update returned a successful result and return identity, otherwise process result error
    if result.success?
      GitHub::SCIM::Result.deliver_scim(@call_options[:serialize_method], result.external_identity, 200)
    else
      deliver_result_error(result)
    end
  end

  # Private: Internal implementation of a DELETE Users endpoint
  #
  # Returns Result object that can either contain an error or an empty result with status code of 204
  def delete_user_internal
    result = provisioner.find(target: @call_options[:target], identity_guid: params[:external_identity_guid])

    # Log the external_id to splunk
    if (log_data = request.env[Rack::RequestLogger::APPLICATION_LOG_DATA])
      log_data["gh.external_identities.external_id"] = result&.external_identity.nil? ? "nil" : result&.external_identity&.external_id
    end

    unless result.success?
      return GitHub::SCIM::Result.deliver_scim_error(404, detail: "Resource #{ params[:external_identity_guid] } not found.")
    end

    external_identity = result.external_identity
    # get existing scim user data and set the active flag to false, which will
    # suspend a user
    user_data = external_identity.scim_user_data
    user_data.replace("active", "False")

    result = provisioner.deprovision \
      target: @call_options[:target],
      user_data: user_data,
      mapper: Platform::Provisioning::ScimMapper,
      identity: external_identity,
      actor_id: current_user.id

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
        deliver_scim(result.serialize_method, result.results, status: result.status_code)
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
      GitHub::SCIM::Result.deliver_scim_error(result.error_code, scim_type: "uniqueness")
    elsif result.forbidden_error?
      GitHub::SCIM::Result.deliver_scim_error(result.error_code, detail: result.error_messages.join("\n"))
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

  def valid_emails?(user_data)
    result = true

    if user_data.emails.present?
      user_data.emails.each do |email|
        if !User.valid_email?(email)
          result = false
          break
        end
      end
    end
    result
  end

  def instrument_emu_onboarding_complete
    enterprise = @call_options[:target]
    return unless enterprise&.is_a?(Business)
    return unless enterprise.enterprise_managed_user_enabled?
    return unless enterprise.trial?
    return unless enterprise.external_provider
    external_identities = ExternalIdentity.by_provider(enterprise.external_provider).not_disabled_and_deleted.limit(2)
    return if external_identities.count > 1

    GitHub.logger.info(
      "info.message": "EMU onboarding complete",
      "gh.business_id": enterprise.id,
      "gh.business_slug": enterprise.slug,
    )
  end
end
