# typed: true
# frozen_string_literal: true

module Api::App::GraphqlDependency
  extend T::Helpers

  requires_ancestor { Api::App::ErrorDependency }

  # Public: Delivers an error response based on a platform result error.
  #
  # options - Optional Hash to customize the error output.  Extra options are
  #           passed through to #deliver.
  #           :message           - String describing the error.
  #           :documentation_url - String URL for the documentation that will
  #                                help the user understand and resolve the
  #                                error (optional)
  #                                (default: 'https://developer.github.com').
  #           :errors            - A non-empty GraphQL::Client::Errors object
  #           :resource          - A String resource name that these errors
  #                                apply to
  #           :status            - Optional HTTP status. GraphQL errors can
  #                                usually figure out their own status code.
  #
  # Returns a String body to be used as the response of this request.
  def deprecated_deliver_graphql_error(options)
    options = options.dup
    status = options.delete(:status)

    raise ArgumentError, "A resource must be passed to #{__method__}" unless options[:resource].present?

    resource = options.delete(:resource)

    if !resource.is_a?(String)
      Failbot.report(ArgumentError.new("Resource of type `#{resource.class.name}` is not a string."))
      resource = resource.class.name
    end

    errors = options[:errors].try(:all)
    raise ArgumentError, "Empty error objects cannot be passed to #{__method__}" unless errors.try(:any?)

    if errors.details["data"].any? { |e| e["type"] == Platform::Errors::Unauthorized::Read.type }
      status ||= 404
      deliver_error(status)
    elsif (_error = errors.details["data"].find { |e| e["type"] == Platform::Errors::Unauthorized::Write.type })
      # We could, in theory, deliver a 403 here. But historically the REST API
      # has not distinguished between "can't see it" and "can see it, but can't
      # do that." We continue this tradition into the era of graphql.
      status ||= 404
      deliver_error(status)
    elsif (service_unavailable = errors.details["data"].find { |e| e["type"] == Platform::Errors::ServiceUnavailable.type })
      status ||= 503
      field_formatted_errors = [{ code: :service_unavailable, message: service_unavailable["message"] }]
      deliver_error(status, options.merge(errors: field_formatted_errors))
    else
      field_formatted_errors = []
      status ||= 422
      errors.details["data"].each do |error|
        if error["type"] == Platform::Errors::Validation::Field.type
          field_formatted_errors.push({
            resource: resource,
            code: :custom,
            field: error["field"],
            message: error["message"],
          })
        else
          field_formatted_errors.push({
            resource: resource,
            code: :unprocessable,
            field: "data",
            message: error["message"],
          })
        end
      end
      deliver_error(status, options.merge(errors: field_formatted_errors))
    end
  end

  # Halt the request with an error.
  #
  # See deliver_graphql_error for arguments and return values.
  def deprecated_deliver_graphql_error!(*args)
    halt T.unsafe(self).deprecated_deliver_graphql_error(*args)
  end

  def has_graphql_mutation_errors?(results)
    results = results.to_h
    mutation_name = results["data"].keys.first
    results["data"][mutation_name]["errors"].present?
  end

  def deliver_graphql_mutation_errors(results, opts = {}, resource:, input_variables: nil)
    results = results.to_h
    mutation_name = results["data"].keys.first

    if resource && !resource.is_a?(String)
      Failbot.report(ArgumentError.new("Resource of type `#{resource.class.name}` is not a string."))
      resource = resource.class.name
    end

    errors = results["data"][mutation_name]["errors"].map do |error|
      path = path_with_integer_based_index(error["path"])

      if path
        api_error(resource, error["attribute"], :invalid, value: input_variables.dig(*path))
      else
        api_error(resource, error["attribute"], :invalid)
      end
    end

    deliver_error! 422, opts.merge(errors: errors)
  end

  def deliver_graphql_mutation_errors!(*args, **options)
    halt T.unsafe(self).deliver_graphql_mutation_errors(*args, **options)
  end

  # Public
  # Returns true if there are top-level errors or errors on a mutation field
  def has_any_graphql_errors?(results)
    has_graphql_system_errors?(results) || has_graphql_mutation_errors?(results)
  end

  # Private
  # Returns true if the `results` have any top-level errors
  def has_graphql_system_errors?(results)
    results.errors.all.any?
  end

  # Public
  # Figure out what kind of errors are present in `results` and return
  # a response based on them, halting control flow.
  def deliver_graphql_error!(results, opts = {}, inputs: nil, resource: nil)
    if resource && !resource.is_a?(String)
      Failbot.report(ArgumentError.new("Resource of type `#{resource.class.name}` is not a string."))
      resource = resource.class.name
    end

    if has_graphql_system_errors?(results)
      halt deliver_graphql_system_error(results, opts, inputs: inputs, resource: resource)
    end

    if has_graphql_mutation_errors?(results)
      halt deliver_graphql_mutation_errors(results, opts, input_variables: inputs, resource: resource)
    end
  end

  # Private
  # Get root errors in `results` and return a REST response based on them.
  def deliver_graphql_system_error(results, opts = {}, inputs: nil, resource: nil)
    errors = results.errors.all.details["data"]
    error_types = errors.map { |err| err["type"] }

    if !(error_types & %w(NOT_FOUND UNAUTHENTICATED UNAUTHORIZED-READ UNAUTHORIZED-WRITE)).empty?
      status  = 404
      message = "Not Found"
    elsif error_types.any? { |err| err == "FORBIDDEN" }
      status  = 403
      message = "Forbidden"
    elsif error_types.any? { |err| err == "REPOSITORY_MIGRATION" }
      status  = 403
      message = "Repository has been locked for migration."
    elsif error_types.any? { |err| err == "REPOSITORY_ARCHIVED" }
      status  = 403
      message = "Repository was archived so is read-only."
    elsif error_types.any? { |err| err == "ISSUES_DISABLED" }
      status  = 410
      message = "Issues are disabled for this repository."
    elsif error_types.any? { |err| err == "SERVICE_UNAVAILABLE" }
      status  = 503
      message = "Service Unavailable"
    elsif errors.any? { |err| err["message"].starts_with?(GitHub::RateLimitedCreation::ERROR_MESSAGE) }
      status = 403
      message = Api::App::ErrorDependency::ERROR_MESSAGE_RATE_LIMIT
      message += Api::ErrorHelper.rate_limit_message_for_request_id(GitHub.context[:request_id])
      errors = nil
      documentation_url = Api::App::ErrorDependency::DOC_URL_RATE_LIMIT
      log_rate_limited_request
    else
      status  = 422
      message = "Unprocessable Entity"
      errors  = results.errors.all.values.flatten
    end

    options = {}.tap do |hash|
      hash[:message]  = message if message
      hash[:errors]   = errors if errors
      hash[:documentation_url] = documentation_url if documentation_url
    end

    deliver_error status, options
  end
end
