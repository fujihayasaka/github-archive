# typed: strict
# frozen_string_literal: true

module Tapioca
  module Compilers
    # Used for classes that use the Limits API to define limits.
    #
    # For example, for the following class:
    #
    # class Group
    #   include Limits
    #
    #   MAX_MEMBERS = 10
    #
    #   attr_reader :members
    #
    #   limits :members,
    #     to: MAX_MEMBERS,
    #     reached_when: -> { members.size >= MAX_MEMBERS }
    #
    #   def initialize(members)
    #     @members = members
    #   end
    # end
    #
    # An RBI file similar to the following will be generated:
    #
    # class Group
    #   sig { returns(Integer) }
    #   def members_limit; end
    #
    #   sig { params(items: T::Enumerable[Integer]).returns(T::Enumerable[Integer]) }
    #   def members_limit_allowed_new_items(items); end
    #
    #   sig { returns(T::Boolean) }
    #   def members_limit_reached?; end
    #
    #   sig { returns(String) }
    #   def members_limit_reached_message; end
    #
    #   sig { params(items: T::Enumerable[Integer]).returns(T::Boolean) }
    #   def members_limit_will_be_exceeded_with?(items); end
    # end
    #
    class Limits < Tapioca::Dsl::Compiler
      extend T::Generic

      ConstantType = type_member { { fixed: T.class_of(::Limits) } }

      sig { override.returns(T::Enumerable[T::Module[T.anything]]) }
      def self.gather_constants
        all_classes.select { |c| c < ::Limits }
      end

      sig { override.void }
      def decorate
        root.create_path(constant) do |klass|
          constant.defined_limits.each do |name|
            klass.create_method(
              "#{name}_limit",
              return_type: "Integer"
            )
            klass.create_method(
              "#{name}_limit_reached?",
              return_type: "T::Boolean"
            )
            klass.create_method(
              "at_#{name}_limit?",
              return_type: "T::Boolean"
            )
            klass.create_method(
              "#{name}_soft_limit",
              return_type: "Integer"
            )
            klass.create_method(
              "#{name}_soft_limit_reached?",
              return_type: "T::Boolean"
            )
            klass.create_method(
              "at_#{name}_soft_limit?",
              return_type: "T::Boolean"
            )
            klass.create_method(
              "#{name}_allowed_to_be_added",
              return_type: "Integer"
            )
            klass.create_method(
              "#{name}_limit_will_be_exceeded_with?",
              parameters: [create_param("items", type: "T::Enumerable[T.untyped]")],
              return_type: "T::Boolean"
            )
            klass.create_method(
              "#{name}_limit_allowed_new_items",
              parameters: [create_param("items", type: "T::Enumerable[T.untyped]")],
              return_type: "T::Enumerable[T.untyped]"
            )
            klass.create_method(
              "#{name}_limit_reached_message",
              return_type: "String"
            )
          end
        end
      end
    end
  end
end
