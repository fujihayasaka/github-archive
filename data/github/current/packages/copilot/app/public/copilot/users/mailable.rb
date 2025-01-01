# typed: strict
# frozen_string_literal: true

module Copilot
  module Users
    module Mailable
      extend T::Helpers
      include Copilot::Users::Signatures

      abstract!

      sig { override.returns(T::Boolean) }
      def copilot_communication_opt_out?
        # this will usually be false because we aren't implementing this at the user level
        # but we need to implement it to satisfy the interface and for completeness
        # if you really wanna add a user to the flag, have at it.
        return user_object.feature_enabled?(:copilot_communication_opt_out, memoize: false) if has_cfi_access?
        # We DO need to check if the user belongs to an organization that has opted out, either directly or via its
        # parent enterprise.
        if !copilot_organizations.empty?
          return copilot_organizations.any? { |org| Copilot.copilot_communication_opt_out?(org.__getobj__) }
        end
        # We need to check if the user belongs to a standalone business that has opted out.
        emb = user_object.enterprise_managed_business
        return Copilot.copilot_communication_opt_out?(emb) if emb.present?
        copilot_businesses.any? { |business| Copilot.copilot_communication_opt_out?(business.__getobj__) }
      end
    end
  end
end
