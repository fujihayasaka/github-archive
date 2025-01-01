# typed: strict
# frozen_string_literal: true

# Internal: This is a special case to signify that we
# are inheriting the default 'selection' while also granting additional
# access to subjects listed in 'ids'.
#
# We use this to allow cross-target granting of permissions, such as
# the user's dotfiles repository.
#
# Examples:
#
#   InheritSelectionWithIds.new(
#     ids: [42]
#   )
module ScopedInstallations
  module AuthorizationDetails
    module Structs
      class V2
        class InheritSelectionWithIds < T::Struct
          prop :inherit_selection, T::Boolean, default: true
          prop :ids, T::Array[Integer]
        end
      end
    end
  end
end
