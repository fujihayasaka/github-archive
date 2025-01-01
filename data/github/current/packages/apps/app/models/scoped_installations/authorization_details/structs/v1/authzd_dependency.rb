# typed: strict
# frozen_string_literal: true

module ScopedInstallations
  module AuthorizationDetails
    module Structs
      module V1::AuthzdDependency
        extend T::Helpers

        requires_ancestor { V1 }

        sig { returns(T::Array[Authzd::Proto::Attribute]) }
        def authzd_proto_attributes
          self.transform(version: 2).authzd_proto_attributes
        end
      end
    end
  end
end
