# typed: strict
# frozen_string_literal: true

module Copilot
  module OrgEnablement
    class PlanDowngradeComponent < BaseActionDialog

      include GitHub::Memoizer

      sig { returns(String) }
      memoize def title
        "Downgrade Copilot access"
      end

      sig { returns(String) }
      memoize def id
        "copilot-organization-downgrade-dialog"
      end

      sig { returns(String) }
      memoize def confirmation_text
        "Confirm and downgrade"
      end

      sig { returns(Symbol) }
      def confirmation_scheme
        :danger
      end

      sig { returns(String) }
      def enablement
        "business"
      end
    end
  end
end
