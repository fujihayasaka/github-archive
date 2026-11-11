# typed: false
# frozen_string_literal: true

module Platform
  module SchemaPrinter
    def self.print(schema, target:, environment:, serviceowners: nil, federation: false)
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
            schema: schema,
          },
          include_feature_flagged_directive: include_feature_flagged_directive,
          serviceowners: serviceowners,
          federation: federation
        )
        .document
        .to_query_string
    end

    class SchemaToAST < GraphQL::Language::DocumentFromSchemaDefinition
      def initialize(*args, except: nil, include_feature_flagged_directive:, serviceowners:, federation: false, **kwargs)
        super(*args, **kwargs)
        @include_feature_flagged_directive = include_feature_flagged_directive
        @mask = except
        @serviceowners = serviceowners
        @federation = federation
        @federation_reserved_directives = nil
      end

      def document
        doc = super
        doc = remove_federation_types_if_needed(doc)
        doc = add_federation_link_if_needed(doc)
        doc
      end

      def build_directive_nodes(nodes)
        directive_nodes = super

        # Validate that no custom directives conflict with federation reserved names
        validate_no_federation_directive_conflicts(directive_nodes)

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
        node = add_federation_directives_if_needed(object_type, node)
        node = remove_federation_fields_if_needed(object_type, node)
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
        node = add_federation_directives_if_needed(field, node)

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

      def remove_federation_fields_if_needed(object_type, node)
        # Strip any federation root fields added automatically to the Query type by the github-apollo-federation gem.
        # This applies to:
        # - :docs target (documentation shouldn't expose internal federation details)
        # - federation schemas (subgraph schemas shouldn't expose internal federation plumbing)
        should_remove = (@mask.is_a?(Platform::SchemaDocsMask) || @federation) &&
                        object_type.graphql_name == @schema.query.graphql_name
        return node unless should_remove

        federation_fields = Platform::SchemaDocsMask::FEDERATION_QUERY_FIELDS
        filtered_fields = node.fields.reject { |f| federation_fields.include?(f.name) }
        filtered_fields.size != node.fields.size ? node.merge(fields: filtered_fields) : node
      end

      # Remove federation scaffolding types from the schema
      def remove_federation_types_if_needed(doc)
        # Remove when using SchemaDocsMask (the "docs" target) or when generating federation schemas.
        return doc unless @mask.is_a?(Platform::SchemaDocsMask) || @federation

        federation_names = Platform::SchemaDocsMask::FEDERATION_INTERNAL_TYPES
        filtered_defs = doc.definitions.reject do |defn|
          defn.respond_to?(:name) && federation_names.include?(defn.name)
        end

        filtered_defs.size != doc.definitions.size ? doc.merge(definitions: filtered_defs) : doc
      end

      # Adds federation directives (@key, @shareable, etc.) to schema members.
      # These directives are part of the Apollo Federation specification and are used
      # by the github/graph-hopper service for supergraph composition.
      def add_federation_directives_if_needed(schema_member, node)
        # Only add federation directives when generating federation schemas
        return node unless @federation

        # Check if the schema member has federation directives
        return node unless schema_member.respond_to?(:federation_directives)

        federation_directives = schema_member.federation_directives
        return node if federation_directives.empty?

        # Convert federation directives to GraphQL AST nodes
        new_directives = federation_directives.map do |directive|
          directive_args = if directive[:arguments]
            directive[:arguments].map do |arg|
              GraphQL::Language::Nodes::Argument.new(
                name: arg[:name].to_s,
                value: arg[:values]
              )
            end
          else
            []
          end

          GraphQL::Language::Nodes::Directive.new(
            name: directive[:name].to_s,
            arguments: directive_args
          )
        end

        node.merge directives: node.directives + new_directives
      end

      # Add the @link directive for Apollo Federation to the schema.
      # This directive is used by github/graph-hopper to determine which federation spec version is being used.
      def add_federation_link_if_needed(doc)
        # Only add for federation schemas
        return doc unless @federation

        extend_schema_node = federation_extend_schema_node
        return doc unless extend_schema_node && extend_schema_node.directives.any?

        # Add the "extend schema @link(...)" directly to the beginning of the document
        doc.merge(definitions: [extend_schema_node] + doc.definitions)
      end

      # Parse and cache the federation "extend schema @link(...)" node
      # This is used both for adding the @link directive and extracting reserved directive names
      def federation_extend_schema_node
        # Cache the result since this is called multiple times
        return @federation_extend_schema_node if defined?(@federation_extend_schema_node)

        # Only schemas that include ApolloFederation::Schema have federation_sdl
        unless @schema.respond_to?(:federation_sdl)
          @federation_extend_schema_node = nil
          return @federation_extend_schema_node
        end

        # Get the federation SDL which includes the @link directive
        federation_sdl_string = @schema.federation_sdl

        # Parse it to extract the schema extension with @link directive
        federation_doc = GraphQL::Language::Parser.parse(federation_sdl_string)

        # Find the "extend schema" node with @link directive
        @federation_extend_schema_node = federation_doc.definitions.find do |defn|
          defn.is_a?(GraphQL::Language::Nodes::SchemaExtension)
        end

        @federation_extend_schema_node
      end

      # Extract the list of federation reserved directive names from the @link directive's import argument
      def federation_reserved_directives
        return @federation_reserved_directives if @federation_reserved_directives

        # Retrieve the "extend schema" node
        extend_schema_node = federation_extend_schema_node
        return [] unless extend_schema_node

        # Find the @link directive on the schema extension
        link_directive = extend_schema_node.directives.find { |d| d.name == "link" }
        return [] unless link_directive

        # Find the import argument on the @link directive
        import_arg = link_directive.arguments.find { |arg| arg.name == "import" }
        return [] unless import_arg

        # Extract directive names from the import list
        # The import value is an array of string nodes like ["@key", "@shareable", ...]
        @federation_reserved_directives = if import_arg.value.respond_to?(:map)
          import_arg.value.map do |item|
            # Get the string value and strip the @ prefix since we're comparing directive names
            value_str = item.respond_to?(:value) ? item.value : item.to_s
            value_str.delete_prefix("@")
          end
        else
          []
        end

        @federation_reserved_directives
      end

      # Validate that no custom directives use names reserved by the Apollo Federation spec.
      # This prevents conflicts when generating federation schemas
      #
      # Example of what would be caught:
      #   class Key < GraphQL::Schema::Directive
      #     graphql_name "key"
      #     ...
      #   end
      # Such a directive would conflict with the federation @key directive.
      def validate_no_federation_directive_conflicts(directive_nodes)
        # Only validate when generating federation schemas
        return unless @federation

        reserved_directives = federation_reserved_directives
        return if reserved_directives.empty?

        directive_nodes.each do |directive_node|
          directive_name = directive_node.name

          if reserved_directives.include?(directive_name)
            raise ArgumentError, # rubocop:disable GitHub/UsePlatformErrors
              "Directive name '@#{directive_name}' is reserved by the Apollo Federation spec and cannot be used as a custom directive. " \
              "Please rename your directive to avoid conflicts with federation directives. " \
              "Reserved names: #{reserved_directives.sort.map { |d| "@#{d}" }.join(', ')}"
          end
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
