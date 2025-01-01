# typed: true
# frozen_string_literal: true

module RuleEngine
  module ParameterSchema
    class Base
      extend T::Helpers
      extend T::Sig

      abstract!

      attr_reader :type, :name, :display_name, :description, :required, :root, :internal, :default_value, :ui_control, :feature_flag, :min_ghes_version, :beta, :beta_api, :aliases, :transform_fn

      # visibility_fn    - function to apply to determine if the parameter is visible. If visibility is determined by a feature flag
      #                    use the feature_flag parameter instead. Regardless of visibility, this parameter will be visible in the API because there is no context.
      #                    Therefore, the backend must determine if the parameter is valid.
      # feature_flag     - feature flag to apply to determine if the parameter is visible. This attribute is necessary to determine availability
      #                    in the APIs.
      # beta             - when true, add a note that the field is in beta
      # beta_api         - when true, add a note to the api that the field is in beta and subject to change
      # publish_api      - by default, uses the value of the feature flag to determine if it should be visible in the API. However, each field can override that
      # description_api  - Optionally provide a different description for the API
      # min_ghes_version - minimum GHES version required for this parameter to be visible in the APIs
      def initialize(type:, name:, display_name:, description:, required: false, root: false, org_only: false, internal: false,
                    supported_plan: nil, default_value: nil, validator: nil, ui_control: nil, visibility_fn: nil,
                    feature_flag: nil, min_ghes_version: nil, beta: false, beta_api: false, publish_api: nil, description_api: nil, aliases: [], transform_fn: nil)
        @type = type
        @name = name
        @display_name = display_name
        @description = description
        @required = required
        @root = root
        @internal = internal
        @org_only = org_only
        @supported_plan = supported_plan
        @default_value = default_value
        @validator = validator
        @ui_control = ui_control
        @visibility_fn = visibility_fn
        @feature_flag = feature_flag
        @min_ghes_version = min_ghes_version
        @beta = beta
        @beta_api = beta_api
        @publish_api = publish_api
        @description_api = description_api
        @aliases = aliases
        @transform_fn = transform_fn
      end

      # By default, false when a feature flag is present
      # - REST API docs are not published but REST API requests can be made on repos where the feature flag is enabled
      # - GraphQL requests require passing the feature flag in the request header
      #
      # Keep in mind that there is no official beta for the APIs.
      # Once published, we have to be cautious about changes as they may break integrators
      #
      # If this method is overridden, keep in mind you can can delete the overriding method once the feature flag is removed
      def publish_api
        @publish_api || feature_flag.nil?
      end

      def is_feature_enabled?(source)
        return true if feature_flag.nil?

        if source.is_a?(Repository)
          source.async_scoped_feature_flag_enabled?(feature_flag).sync
        else
          source.feature_enabled?(feature_flag) || !!(source.owner&.feature_enabled?(feature_flag))
        end
      end

      def is_visible_by_source?(source)
        is_org_source = source.is_a?(Organization)
        is_repo_source = source.is_a?(Repository)

        return false unless is_feature_enabled?(source)
        return false if @org_only && !is_org_source && (is_repo_source && !source.in_organization?)
        return false if @internal
        return false if @supported_plan.present? && !source.plan_supports?(@supported_plan)
        return false if @visibility_fn.present? && !@visibility_fn.call(source)

        true
      end

      def validate_parameters(context, params); end

      # Performs a transformation on transformable. This will modify the transformable object in place.
      # Not expected to return anything.
      # transformable - the entity that will be transformed. The type depends on whether this is called
      #                 by a field, object, or array
      sig { params(transformable: T.untyped).void }
      def transform_parameters!(transformable)
        transform_parameters(transformable)
      end

      # Performs a transformation on transformable if a transform_fn is present
      # Same as transform_parameters! but returns the transformed value
      # transformable - the entity that will be transformed. The type depends on whether this is called
      #                 by a field, object, or array
      sig { params(transformable: T.untyped).returns(T.untyped) }
      def transform_parameters(transformable)
        return unless transform_fn.present?
        transform_fn.call(transformable)
      end

      # If the API has a description, use it. Otherwise, use the description
      sig { returns(String) }
      def description_api
        @description_api || description
      end

      protected

      def apply_custom_validator(context, value, errors)
        return unless @validator.present?

        @validator.call(context, value, errors)
      end
    end
  end
end
