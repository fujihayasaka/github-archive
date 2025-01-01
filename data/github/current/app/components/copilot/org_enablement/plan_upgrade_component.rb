# typed: strict
# frozen_string_literal: true

module Copilot
  module OrgEnablement
    class PlanUpgradeComponent < BaseActionDialog
      extend T::Sig

      include GitHub::Memoizer

      sig { returns(String) }
      memoize def title
        "Upgrade#{@organizations.count != 1 ? @organizations.count : ""} #{'organization'.pluralize(@organizations.count)} to Copilot Enterprise"
      end

      sig { returns(String) }
      memoize def id
        "copilot-organization-upgrade-dialog"
      end

      sig { returns(String) }
      memoize def confirmation_text
        "Confirm and upgrade"
      end

      sig { returns(Symbol) }
      def confirmation_scheme
        :primary
      end

      sig { returns(String) }
      def enablement
        "enterprise"
      end
    end
  end
end
