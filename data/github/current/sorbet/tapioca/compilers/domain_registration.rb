# typed: strict
# frozen_string_literal: true

module Tapioca
  module Compilers
    # The register_domain method creates a method to access a singleton instance of a domain object
    # for the duration of a request.
    #
    # Example:
    # ~~~rb
    # module Stars
    #   class Domain < GH::Domain::Base
    #     register_domain Stars, Stars::Domain, -> { new(:foo) }
    #   end
    # end
    # ~~~
    #
    # enables `Stars.domain` => `#<Stars::Domain:0x00007f8e0b0b3b00>`
    #
    # Generates the following RBI file:
    #
    # ~~~rb
    # module Stars
    #   include GeneratedDomainRegistrationMethods
    #
    #   module GeneratedDomainRegistrationMethods
    #     sig { returns(Stars::Domain) }
    #     def domain; end
    #   end
    # end
    # ~~~

    class DomainRegistration < Tapioca::Dsl::Compiler
      ConstantType = type_member { { fixed: Module } }

      sig { override.returns(T::Enumerable[Module]) }
      def self.gather_constants
        ::GH::Domain::Registration.registered_domains_map.keys
      end

      sig { override.void }
      def decorate
        root.create_path(constant) do |model|
          model.create_module("GeneratedDomainRegistrationMethods") do |mod|
            return_type = ::GH::Domain::Registration.registered_domains_map[constant]
            mod.create_method("domain", return_type: return_type.to_s)
          end

          model.create_extend("GeneratedDomainRegistrationMethods")
        end
      end
    end
  end
end
