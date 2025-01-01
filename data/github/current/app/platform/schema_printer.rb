# typed: false
# frozen_string_literal: true

module Platform
  module SchemaPrinter
    def self.print(schema, target:, environment:, serviceowners: nil)
      case target
      when :docs
        # This is a special target: it's the public schema, but with all feature-flagged members hidden.
        include_feature_flagged_directive = false
        mask = Platform::SchemaDocsMask.new(:public, environment: environment)
      when :internal, :public
        include_feature_flagged_directive = true
        mask = Platform::SchemaVersionMask.new(target, environment: environment)
      else
        raise ArgumentError, "unexpected target: #{target.inspect}" # rubocop:disable GitHub/UsePlatformErrors
      end

      SchemaToAST
        .new(
          schema,
          except: mask,
          context: {
            mask: mask,
          },
          include_feature_flagged_directive: include_feature_flagged_directive,
          serviceowners: serviceowners
        )
        .document
        .to_query_string
    end

    class SchemaToAST < GraphQL::Language::DocumentFromSchemaDefinition
      def initialize(*args, except: nil, include_feature_flagged_directive:, serviceowners:, **kwargs)
        super(*args, **kwargs)
        @include_feature_flagged_directive = include_feature_flagged_directive
        @mask = except
        @serviceowners = serviceowners
      end

      def build_directive_nodes(nodes)
        directive_nodes = super

        if @mask.target == :public && @include_feature_flagged_directive
          directive_nodes << build_directive_node(FeatureFlagged)
          directive_nodes << build_directive_node(RequiredCapabilities)
        end

        directive_nodes << build_directive_node(Preview)                     if @mask.target == :public
        directive_nodes << build_directive_node(PossibleTypes)
        directive_nodes << build_directive_node(UnderDevelopment::Directive) unless @mask.target == :public
        directive_nodes << build_directive_node(Internal)                    unless @mask.target == :public
        directive_nodes << build_directive_node(ServiceMapping)              if @mask.target == :internal
        directive_nodes << build_directive_node(UseNextGlobalIdFormat)       if @mask.target == :internal && @mask.environment == :dotcom
        directive_nodes
      end

      def build_scalar_type_node(scalar_type)
        node = super
        node = add_feature_flag_directive_if_needed(scalar_type, node)
        node = add_required_capabilities_directive_if_needed(scalar_type, node)
        node = add_preview_directive_if_needed(scalar_type, node)
        node = add_visibility_directive_if_needed(scalar_type, node)
        node = add_service_mapping_directive_if_needed(scalar_type, node)
        node
      end

      def build_object_type_node(object_type)
        node = super
        node = add_feature_flag_directive_if_needed(object_type, node)
        node = add_required_capabilities_directive_if_needed(object_type, node)
        node = add_preview_directive_if_needed(object_type, node)
        node = add_visibility_directive_if_needed(object_type, node)
        node = add_service_mapping_directive_if_needed(object_type, node)
        node = add_use_next_global_id_format_directive_if_needed(object_type, node)
        node
      end

      def build_interface_type_node(interface_type)
        node = super
        node = add_feature_flag_directive_if_needed(interface_type, node)
        node = add_required_capabilities_directive_if_needed(interface_type, node)
        node = add_preview_directive_if_needed(interface_type, node)
        node = add_visibility_directive_if_needed(interface_type, node)
        node = add_service_mapping_directive_if_needed(interface_type, node)
        node
      end

      def build_field_node(field)
        node = super

        node = add_visibility_directive_if_needed(field, node)
        node = add_feature_flag_directive_if_needed(field, node)
        node = add_required_capabilities_directive_if_needed(field, node)
        node = add_preview_directive_if_needed(field, node)
        node = add_service_mapping_directive_if_needed(field, node)

        node
      end

      def build_argument_node(argument)
        node = super
        node = add_feature_flag_directive_if_needed(argument, node)
        node = add_required_capabilities_directive_if_needed(argument, node)
        node = add_preview_directive_if_needed(argument, node)
        node = add_visibility_directive_if_needed(argument, node)
        node = add_possible_types_if_needed(argument, node)
        node
      end

      def build_union_type_node(union_type)
        node = super
        node = add_feature_flag_directive_if_needed(union_type, node)
        node = add_required_capabilities_directive_if_needed(union_type, node)
        node = add_preview_directive_if_needed(union_type, node)
        node = add_visibility_directive_if_needed(union_type, node)
        node = add_service_mapping_directive_if_needed(union_type, node)

        node
      end

      def build_enum_type_node(enum_type)
        node = super
        node = add_feature_flag_directive_if_needed(enum_type, node)
        node = add_required_capabilities_directive_if_needed(enum_type, node)
        node = add_preview_directive_if_needed(enum_type, node)
        node = add_visibility_directive_if_needed(enum_type, node)
        node = add_service_mapping_directive_if_needed(enum_type, node)
        node
      end

      def build_enum_value_node(enum_value)
        node = super
        node = add_feature_flag_directive_if_needed(enum_value, node)
        node = add_required_capabilities_directive_if_needed(enum_value, node)
        node = add_preview_directive_if_needed(enum_value, node)
        node = add_visibility_directive_if_needed(enum_value, node)
        node
      end

      def build_input_object_node(input_object)
        node = super
        node = add_feature_flag_directive_if_needed(input_object, node)
        node = add_required_capabilities_directive_if_needed(input_object, node)
        node = add_preview_directive_if_needed(input_object, node)
        node = add_visibility_directive_if_needed(input_object, node)
        node = add_service_mapping_directive_if_needed(input_object, node)
        node
      end

      private

      def add_use_next_global_id_format_directive_if_needed(schema_member, node)
        return node if @mask.target == :public
        return node if @mask.environment != :dotcom
        return node unless schema_member.respond_to?(:global_id_ready_date) && schema_member.global_id_ready_date.present?

        node.merge directives: node.directives + [GraphQL::Language::Nodes::Directive.new(
          name: UseNextGlobalIdFormat.graphql_name,
          arguments: [
            GraphQL::Language::Nodes::Argument.new(name: "after", value: schema_member.global_id_ready_date),
          ],
        )]
      end

      def add_possible_types_if_needed(argument, node)
        if argument.respond_to?(:loads) && (loads_type = argument.loads)
          case loads_type.kind.name
          when "UNION", "INTERFACE"
            concrete_types = @types.possible_types(loads_type)
            type_is_accessible = @types.type(loads_type.graphql_name)
            abstract_type = if type_is_accessible
              loads_type
            else
              nil
            end
          when "OBJECT"
            type_is_accessible = @types.type(loads_type.graphql_name)
            concrete_types = if type_is_accessible
              [loads_type]
            else
              []
            end

            abstract_type = nil
          else
            raise "Invalid value provided for #{argument.graphql_name}'s `loads:`, received `#{argument.loads}`" # rubocop:disable GitHub/UsePlatformErrors
          end

          if concrete_types.present?
            arguments = [
              GraphQL::Language::Nodes::Argument.new(name: "concreteTypes", value: concrete_types.map(&:graphql_name).sort),
            ]

            if abstract_type
              arguments << GraphQL::Language::Nodes::Argument.new(name: "abstractType", value: abstract_type.graphql_name)
            end

            node = node.merge(directives: node.directives + [GraphQL::Language::Nodes::Directive.new(
              name: PossibleTypes.graphql_name,
              arguments: arguments,
            )])
          end
        end

        node
      end

      def add_feature_flag_directive_if_needed(schema_member, node)
        if @mask.target != :public
          node
        elsif schema_member.respond_to?(:feature_flag) && schema_member.feature_flag.present?
          node.merge directives: node.directives + [GraphQL::Language::Nodes::Directive.new(
            name: FeatureFlagged.graphql_name,
            arguments: [
              GraphQL::Language::Nodes::Argument.new(name: "flag", value: schema_member.feature_flag),
            ],
          )]
        else
          node
        end
      end

      def add_required_capabilities_directive_if_needed(schema_member, node)
        if @mask.target != :public
          node
        elsif schema_member.respond_to?(:required_capabilities) && schema_member.required_capabilities.present?
          node.merge directives: node.directives + [GraphQL::Language::Nodes::Directive.new(
            name: RequiredCapabilities.graphql_name,
            arguments: [
              GraphQL::Language::Nodes::Argument.new(name: "requiredCapabilities", value: schema_member.required_capabilities),
            ],
            )]
        else
          node
        end
      end

      def add_preview_directive_if_needed(schema_member, node)
        if @mask.target != :public
          node
        elsif schema_member.respond_to?(:preview_toggled_by) &&
            schema_member.preview_toggled_by &&
            (preview = schema_member.preview_toggled_by[@mask.preview_environment])

          node = node.merge directives: node.directives + [GraphQL::Language::Nodes::Directive.new(
            name: Preview.graphql_name,
            arguments: [
              GraphQL::Language::Nodes::Argument.new(name: "toggledBy", value: preview.toggled_by),
            ],
          )]
        else
          node
        end
      end

      def add_visibility_directive_if_needed(schema_member, node)
        if !schema_member.respond_to?(:visibility_for)
          node
        else
          visibilities = schema_member.visibility_for(@mask.environment)
          # Arguments from `.define`-based directives below don't have a visibility value
          if visibilities.nil? || visibilities.include?(:public)
            node
          elsif visibilities.include?(:under_development)
            node.merge(directives: node.directives + [GraphQL::Language::Nodes::Directive.new(name: UnderDevelopment::Directive.graphql_name)])
          elsif visibilities.include?(:internal)
            node.merge(directives: node.directives + [GraphQL::Language::Nodes::Directive.new(name: Internal.graphql_name)])
          end
        end
      end

      def add_service_mapping_directive_if_needed(schema_member, node)
        if @mask.target != :internal || # Only print for internal schema
           @mask.environment != :dotcom || # Only print for dotcom
          (!schema_member.respond_to?(:service_mapping)) || # skip anything that doesn't have a service mapping
          (service_mapping = schema_member.service_mapping(serviceowners: @serviceowners)).blank? || # skip anything which has a blank service mapping
          service_mapping == :unknown || # don't label unknown service mappings, also built-in GraphQL fields/types
          schema_member.is_a?(GraphQL::Schema::Field) && service_mapping == schema_member.owner.service_mapping(serviceowners: @serviceowners) # Don't print a field's `@serviceMapping` if it matches its owner type
          node
        else
          node.merge directives: node.directives + [GraphQL::Language::Nodes::Directive.new(
            name: ServiceMapping.graphql_name,
            arguments: [
              GraphQL::Language::Nodes::Argument.new(name: "to", value: "#{GitHub::ServiceMapping::SERVICE_PREFIX}/#{service_mapping}"),
            ],
          )]
        end
      end
    end

    class FeatureFlagged < GraphQL::Schema::Directive
      description "Marks an element of a GraphQL schema as only available with a feature flag activated"

      argument :flag, String, required: true, description: "The identifier of the feature flag that toggles this field."

      locations(
        GraphQL::Schema::Directive::SCALAR,
        GraphQL::Schema::Directive::OBJECT,
        GraphQL::Schema::Directive::FIELD_DEFINITION,
        GraphQL::Schema::Directive::ARGUMENT_DEFINITION,
        GraphQL::Schema::Directive::INTERFACE,
        GraphQL::Schema::Directive::UNION,
        GraphQL::Schema::Directive::ENUM,
        GraphQL::Schema::Directive::ENUM_VALUE,
        GraphQL::Schema::Directive::INPUT_OBJECT,
        GraphQL::Schema::Directive::INPUT_FIELD_DEFINITION,
      )
    end
    private_constant :FeatureFlagged

    class MobileOnly < GraphQL::Schema::Directive
      description "Marks an element of a GraphQL schema as only available to the GitHub Mobile application"

      locations(
        GraphQL::Schema::Directive::SCALAR,
        GraphQL::Schema::Directive::OBJECT,
        GraphQL::Schema::Directive::FIELD_DEFINITION,
        GraphQL::Schema::Directive::ARGUMENT_DEFINITION,
        GraphQL::Schema::Directive::INTERFACE,
        GraphQL::Schema::Directive::UNION,
        GraphQL::Schema::Directive::ENUM,
        GraphQL::Schema::Directive::ENUM_VALUE,
        GraphQL::Schema::Directive::INPUT_OBJECT,
        GraphQL::Schema::Directive::INPUT_FIELD_DEFINITION,
      )
    end
    private_constant :MobileOnly

    class RequiredCapabilities < GraphQL::Schema::Directive
      description "Marks an element of a GraphQL schema as only available with an app capability set"

      argument :required_capabilities, [String], required: true, description: "The identifier of the app capabilities that toggles this field."

      locations(
        GraphQL::Schema::Directive::SCALAR,
        GraphQL::Schema::Directive::OBJECT,
        GraphQL::Schema::Directive::FIELD_DEFINITION,
        GraphQL::Schema::Directive::ARGUMENT_DEFINITION,
        GraphQL::Schema::Directive::INTERFACE,
        GraphQL::Schema::Directive::UNION,
        GraphQL::Schema::Directive::ENUM,
        GraphQL::Schema::Directive::ENUM_VALUE,
        GraphQL::Schema::Directive::INPUT_OBJECT,
        GraphQL::Schema::Directive::INPUT_FIELD_DEFINITION,
        )
    end
    private_constant :RequiredCapabilities

    class Preview < GraphQL::Schema::Directive
      description "Marks an element of a GraphQL schema as only available via a preview header"

      argument :toggled_by, String, required: true, description: "The identifier of the API preview that toggles this field."

      locations(
        GraphQL::Schema::Directive::SCALAR,
        GraphQL::Schema::Directive::OBJECT,
        GraphQL::Schema::Directive::FIELD_DEFINITION,
        GraphQL::Schema::Directive::ARGUMENT_DEFINITION,
        GraphQL::Schema::Directive::INTERFACE,
        GraphQL::Schema::Directive::UNION,
        GraphQL::Schema::Directive::ENUM,
        GraphQL::Schema::Directive::ENUM_VALUE,
        GraphQL::Schema::Directive::INPUT_OBJECT,
        GraphQL::Schema::Directive::INPUT_FIELD_DEFINITION,
      )
    end
    private_constant :Preview

    class Internal < GraphQL::Schema::Directive
      description "Marks an element of a GraphQL schema as internal."

      locations(
        GraphQL::Schema::Directive::SCALAR,
        GraphQL::Schema::Directive::OBJECT,
        GraphQL::Schema::Directive::FIELD_DEFINITION,
        GraphQL::Schema::Directive::ARGUMENT_DEFINITION,
        GraphQL::Schema::Directive::INTERFACE,
        GraphQL::Schema::Directive::UNION,
        GraphQL::Schema::Directive::ENUM,
        GraphQL::Schema::Directive::ENUM_VALUE,
        GraphQL::Schema::Directive::INPUT_OBJECT,
        GraphQL::Schema::Directive::INPUT_FIELD_DEFINITION,
      )
    end
    private_constant :Internal

    class ServiceMapping < GraphQL::Schema::Directive
      description "Defines the catalog service mapping for a given part of the GraphQL schema."

      argument :to, String, required: true, description: "A catalog service name"

      locations(
        GraphQL::Schema::Directive::SCALAR,
        GraphQL::Schema::Directive::OBJECT,
        GraphQL::Schema::Directive::FIELD_DEFINITION,
        GraphQL::Schema::Directive::INTERFACE,
        GraphQL::Schema::Directive::UNION,
        GraphQL::Schema::Directive::ENUM,
        GraphQL::Schema::Directive::INPUT_OBJECT,
      )
    end
    private_constant :ServiceMapping

    class UseNextGlobalIdFormat < GraphQL::Schema::Directive
      description "Specifies if the given type should be using the next GlobalID format."

      argument :after, Platform::Scalars::DateTime, required: true, description: "Date the given type should begin using the new format."

      locations GraphQL::Schema::Directive::OBJECT
    end
    private_constant :UseNextGlobalIdFormat

    class PossibleTypes < GraphQL::Schema::Directive
      description "Defines what type of global IDs are accepted for a mutation argument of type ID."

      argument :concrete_types, [String], required: true, description: "Accepted types of global IDs."
      argument :abstract_type, String, required: false, description: "Abstract type of accepted global ID"

      locations(
        GraphQL::Schema::Directive::INPUT_FIELD_DEFINITION,
      )
    end
  end
end
