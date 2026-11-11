# typed: strict
# frozen_string_literal: true

module Copilot
  module OrgEnablement
    # Components that inherit from this class have test coverage instead.
    # There is no view is associated with `BaseActionDialog`.
    # rubocop:disable ViewComponent/ComponentsHaveUnitTests
    class BaseActionDialog < ApplicationComponent
      extend T::Helpers

      include GitHub::Memoizer

      abstract!

      sig { params(business: ::Business, organizations: T::Array[::Organization]).void }
      def initialize(business:, organizations:)
        @business = business
        @organizations = organizations
      end

      sig { returns(String) }
      memoize def billing_end_date
        @business.next_metered_billing_cycle_starts_at.to_date.strftime("%d %B %Y")
      end

      sig { returns(String) }
      memoize def billing_overview_path
        enterprise_billing_path(@business)
      end

      sig { returns(String) }
      memoize def form_submit_path
        if @organizations.size > 1
          update_settings_copilot_bulk_org_enablement_enterprise_path(@business)
        else
          update_settings_copilot_individual_org_enablement_enterprise_path(@business)
        end
      end

      sig { returns(Integer) }
      memoize def org_seat_count
        Copilot::Seat
          .where(organization_id: @organizations.map(&:id))
          .pluck(:assigned_user_id)
          .uniq
          .count
      end
    end
  end
end
