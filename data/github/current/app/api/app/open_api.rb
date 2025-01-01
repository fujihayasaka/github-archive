# typed: true
# frozen_string_literal: true

require "open_api"

# OpenAPI integration for `Api::App` subclasses.
module Api::App::OpenApi
  extend T::Helpers

  requires_ancestor { Api::App }

  def validate_openapi
    GitHub.tracer.in_span("api.app-after", kind: :internal, attributes: {
      "code.namespace" => "validate_openapi"
    }) do |_span|
      return unless env["openapi.validation_enabled"] == true
      return if env["openapi.skip_validation"] == true
      return if GitHub.context[:openapi_skip_validation]

      env["openapi.operation"] = @operation
      env["openapi.validation_errors"] = {}

      return if @request.head?
      return if @request.options?

      validator = OpenApi::Validation::Validator.new(
        @request,
        @operation,
        validate_request_body: false,
        disable_additional_properties: true,
        response_media_type_override: env["openapi.response_media_type_override"]
      )

      # We validate the response before the request because the request might be invalid but the api specifically handles the case and returns an error.
      # Doing the validation in this order ensures that both request/response errors are reported in the
      # test failures.
      response_errors = validator.validate_response(@response.status, @response.headers, @response.body)

      if @response.status.to_i < 400
        request_errors = validator.validate_request unless env["openapi.skip_openapi_request_validation"]
        env["openapi.validation_errors"][:request]  = request_errors
        env["openapi.validation_errors"][:response] = response_errors
      end
    end
  end

  sig { params(operation: OpenApi::Description::Operation).returns(String) }
  def build_documentation_url(operation)
    if operation.documentation_url
      documentation_uri = URI.parse(operation.documentation_url)
      # Remove any Enterprise-specific prefix added by the evaluated ${externalDocsUrl}
      documentation_path = T.must(documentation_uri.path).sub(%r{\A.*?/rest}, "/rest")

      url = "#{documentation_path}##{documentation_uri.fragment}"
    else
      url = default_documentation_url
    end

    url
  end

  module ClassMethods
    # This method returns a maybe-modified block using the given `operation_ids:` config
    def route_with_operation_ids(verb, path, options, &original_block)
      operation_ids = options[:operation_ids]

      annotating_block = nil

      if operation_ids
        operations = {}
        operation_ids.each do |operation_id|
          if operation = OpenApi::Description::Operation.load(operation_id)
            ensure_routable_operation!(operation, normalize_verb(verb))
            operations[operation_id] = operation
          end
        end

        annotating_block = build_annotating_block(
          method_name: "operations #{operations.keys.join(':')} (#{verb})",
          operations: operations,
          impl_block: original_block,
        )
      end

      annotating_block || original_block
    end

    # This method returns a maybe-modified block using the given `operation_id:` config
    def route_with_operation_id(verb, path, options, &original_block)
      operation_id = options[:operation_id]

      annotating_block = nil

      if operation_id
        if OpenApi::IGNORE_REASONS.include?(operation_id)
          annotating_block = build_annotating_block(
            method_name: "ignored_operation #{verb} #{path}",
            operation: OpenApi::Description::Operation.new(operation_id, ignored: true),
            impl_block: original_block,
          )
        else
          operation = OpenApi::Description::Operation.load(operation_id)

          if operation
            ensure_routable_operation!(operation, normalize_verb(verb))
            annotating_block = build_annotating_block(
              method_name: "operation #{operation_id} (#{verb})",
              operation: operation,
              impl_block: original_block,
            )
          end
        end
      end

      annotating_block || original_block
    end

    private

    def build_annotating_block(method_name:, operation: nil, operations: nil, impl_block:)
      T.bind(self, Module)
      # Similar to Sinatra::Base#compile!; defining a method vs using instance_eval allows
      # operation implementations to use `return`.
      if method_defined?(method_name)
        raise ArgumentError, "Duplicate method name: #{method_name}"
      else
        define_method(method_name, &impl_block)
      end

      ->(*args) {
        T.bind(self, Api::App)
        if operation
          # assign the operation for use in contract testing, runtime validation, etc.
          @operation         = operation
          @route_owner       = @operation.route_owner
          @documentation_url = build_documentation_url(@operation)
        end

        if operations
          if deprecated_operation = operations.detect { |_id, op| op.deprecated? }
            # if the incoming request is via a deprecated route, then set the @operation
            # to the deprecated operation from the operations_ids array.
            if @request.env[GitHub::Routers::Api::DEPRECATED_ROUTE]
              @operation = deprecated_operation.last
            end

            @operation ||= operations.detect { |_id, op| !op.deprecated? }.last

            @route_owner       = @operation.route_owner
            @documentation_url = build_documentation_url(@operation)
          elsif GitHub.flipper[:openapi_set_preferred_operation_safer].enabled?
            if GitHub.enterprise?
              matches = operations.filter { |_, op| op.has_enterprise_release? }
              if matches.length == 1
                # we have only one match that includes GHES - assign this to the operation field
                @operation = matches.first[1]
              elsif matches.length > 1
                # we have multiple operations that include GHES - assign the set
                @operations = matches
              else
                # no matches found that include GHES - revert to the original behaviour
                @operations = operations
              end
            else
              matches = operations.filter { |_, op| !op.has_enterprise_release? }
              if matches.length == 1
                # we have only one match that excludes GHES - assign this to the operation field
                @operation = matches.first[1]
              elsif matches.length > 1
                # we have multiple operations that exclude GHES - assign the set
                @operations = matches
              else
                # no matches found, which suggests we have operations targeting all releases
                # -> revert to the original behaviour
                @operations = operations
              end
            end

            if @operation
              @route_owner       = @operation.route_owner
              @documentation_url = build_documentation_url(@operation)
            end
          else
            # if neither operation is deprecated then we want to just set @operations
            @operations = operations
          end
        end
        GitHub.tracer.in_span("api.endpoint", kind: :internal) do |_span|
          # call the original block
          if impl_block.arity != 0
            T.unsafe(self).send(method_name, *args)
          else
            send(method_name)
          end
        end
      }
    end

    # Ensures that the given operation is configured correctly for the desired routing
    #
    # @param operation [Hash] the OpenAPI operation description
    # @param routed_verb [String] the HTTP method/verb
    #
    # @return [void]
    # @raise [ArgumentError] when the operation isn't appropriate for routing
    def ensure_routable_operation!(operation, routed_verb)
      T.bind(self, Module)
      required_verb = operation.http_method
      alternative_verbs = operation.alternative_http_methods
      unless required_verb || alternative_verbs
        raise ArgumentError, "OpenAPI operation with ID #{operation.id} does not define #{OpenApi::Description::Operation::HTTP_METHOD_PROPERTY_PATH.join(".")}"
      end
      unless (routed_verb == required_verb) || (alternative_verbs && alternative_verbs.include?(routed_verb))
        raise ArgumentError, "OpenAPI operation with ID #{operation.id} defines #{OpenApi::Description::Operation::HTTP_METHOD_PROPERTY_PATH.join(".")} as #{required_verb}, not #{routed_verb}"
      end
    end

    # Normalize HTTP verb/method names for comparison purposes.
    #
    # Downcases and converts HEAD -> GET
    #
    # @param verb [String] the HTTP verb
    #
    # @return [String]
    def normalize_verb(verb)
      verb = verb.downcase
      verb == "head" ? "get" : verb
    end
  end

  mixes_in_class_methods(ClassMethods)

  # Check whether a given changeset is active in the currently selected API version.
  #
  # @param changeset_name [Symbol, String] the changeset name
  #
  # @return [Boolean]
  def changeset_active?(changeset_name)
    @selected_api_version && @selected_api_version.changeset_active?(changeset_name)
  end
end
