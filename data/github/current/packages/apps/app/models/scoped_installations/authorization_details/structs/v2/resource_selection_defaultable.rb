# typed: strict
# frozen_string_literal: true

module ScopedInstallations
  module AuthorizationDetails
    module Structs
      module V2::ResourceSelectionDefaultable
        extend T::Helpers

        interface!

        sig { abstract.returns(V2::ResourceSelection) }
        def default_value; end
      end
    end
  end
end
