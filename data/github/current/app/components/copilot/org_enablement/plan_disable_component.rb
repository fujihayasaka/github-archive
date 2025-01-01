# typed: strict
# frozen_string_literal: true

module Copilot
  module OrgEnablement
    class PlanDisableComponent < BaseActionDialog
      extend T::Sig

      include GitHub::Memoizer

      sig { returns(String) }
      memoize def title
        "Remove Copilot access for#{@organizations.count != 1 ? " #{@organizations.count}" : ""} #{'organization'.pluralize(@organizations.count)}"
      end

      sig { returns(String) }
      memoize def id
        "copilot-organization-disable-dialog"
      end

      sig { returns(String) }
      memoize def confirmation_text
        "Confirm and remove seats"
      end

      sig { returns(Symbol) }
      memoize def confirmation_scheme
        :danger
      end

      sig { returns(String) }
      memoize def enablement
        "disable"
      end

      sig { returns(T::Array[Copilot::Organization]) }
      def copilot_organizations
        @organizations.map { |o| Copilot::Organization.new(o) }
      end

      sig { returns(Integer) }
      def total_cost
        org_ids = @organizations.map(&:id).compact

        original_method = @business.method(:organization_ids)
        @business.define_singleton_method(:organization_ids) do
          org_ids
        end

        cost_for_removed_orgs = Copilot::Business.new(@business).total_cost

        @business.define_singleton_method(:organization_ids, original_method)
        cost_for_all_orgs = Copilot::Business.new(@business).total_cost

        cost_for_all_orgs - cost_for_removed_orgs
      end
    end
  end
end
