# typed: strict
# frozen_string_literal: true

module Tapioca
  module Compilers
    # The accessor method registers a domain accessor class as a sub domain of another domain accessor.

    class DomainAccessor < Tapioca::Dsl::Compiler
      ConstantType = type_member { { fixed: T.class_of(GH::Domain::Base) } }

      sig { override.returns(T::Enumerable[Module]) }
      def self.gather_constants
        descendants_of(::GH::Domain::Base)
      end

      sig { override.void }
      def decorate
        root.create_path(constant) do |domain_class|
          domain_class.create_module("GeneratedDomainAccessorMethods") do |mod|
            constant.accessors.each_pair do |method_name, accessor_class|
              mod.create_method(method_name.to_s, return_type: accessor_class.to_s)
            end
          end
          domain_class.create_include("GeneratedDomainAccessorMethods")
        end
      end
    end
  end
end
