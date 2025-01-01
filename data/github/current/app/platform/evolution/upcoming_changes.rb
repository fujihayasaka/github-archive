# typed: true
# frozen_string_literal: true
module Platform
  module Evolution
    # Gathers upcoming changes from a Schema object.
    # See Platform::Evolution::Change
    class UpcomingChanges
      attr_reader :changes

      def initialize(schema, target:, environment:)
        @schema = schema
        @changes = []
        @type_map = {}

        # the filter property will be removed in the 2.1 version of the graphQL gem
        filter = ->(member, ctx) { member.visible?(ctx) }

        @warden = T.unsafe(GraphQL::Schema::Warden).new(
            context: {
              mask: Platform::SchemaVersionMask.new(target, environment: environment),
            },
            schema: @schema,
          )
        visit_schema(@schema)
      end

      def switch_flags
        flags = changes.map { |upcoming_change| upcoming_change.change.switch_flag }
        flags.uniq
      end

      def to_yaml
        sorted_changes = changes.sort_by { |change| [change.apply_on, change.location] }
        { "upcoming_changes" => sorted_changes.map { |change| change.to_h.stringify_keys } }.to_yaml
      end

      private

      attr_reader :warden

      def visit_field(field, type)
        if change = field.upcoming_change
          @changes << Platform::Evolution::UpcomingChange.new(change, path: [type])
        end

        warden.arguments(field).each { |arg| visit_argument(arg, field, type) }
        visit_type(field.type)
      end

      def visit_argument(argument, field, type)
        if change = argument.upcoming_change
          @changes << Platform::Evolution::UpcomingChange.new(change, path: [type, field])
        end

        visit_type(argument.type)
      end

      def visit_input_field(input_field, input_type)
        if change = input_field.upcoming_change
          @changes << Platform::Evolution::UpcomingChange.new(change, path: [input_type])
        end

        visit_type(input_field.type)
      end

      def visit_enum_value(enum_value, enum)
        if change = enum_value.upcoming_change
          @changes << Platform::Evolution::UpcomingChange.new(change, path: [enum])
        end
      end

      def visit_schema(schema)
        warden.types.each { |_name, type| visit_type(type) }
      end

      def visit_type(member)
        type_defn = member.unwrap
        prev_type = @type_map[type_defn.graphql_name]
        return if prev_type

        @type_map[type_defn.graphql_name] = type_defn

        case type_defn.kind.name
        when "OBJECT"
          warden.interfaces(type_defn).each { |iface| visit_type(iface) }
          warden.fields(type_defn)
            .select { |field| warden.visible_field?(field) }
            .each { |field| visit_field(field, type_defn) }
        when "INTERFACE"
          warden.fields(type_defn)
            .select { |field| warden.visible_field?(field) }
            .each { |field| visit_field(field, type_defn) }
        when "UNION"
          warden.possible_types(type_defn).each { |possible_type| visit_type(possible_type) }
        when "INPUT_OBJECT"
          warden.arguments(type_defn).each { |arg| visit_input_field(arg, type_defn) }
        when "ENUM"
          warden.enum_values(type_defn)
          .select { |enum_value| warden.visible_enum_value?(enum_value) }
          .each { |enum_value| visit_enum_value(enum_value, type_defn) }
        end
      end
    end
  end
end
