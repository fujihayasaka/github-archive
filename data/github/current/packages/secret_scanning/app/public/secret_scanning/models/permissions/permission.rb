# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    module Permissions
      class Permission < T::Struct
        # for PATv1, the value will be the scope (ie "repo" or "repo:read" or "admin:org")
        # for PATv2, the value will be the target (ie "metadata")
        const :value, String

        # for PATv1, the group will be a display version of the parent scope (ie "repo" or "org")
        # for PATv2, the group will be a display version of the permission ("Read" or "Read and Write")
        const :group, String

        prop :deleted, T::Boolean, default: false
      end
    end
  end
end
