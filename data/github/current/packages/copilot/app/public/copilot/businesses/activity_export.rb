# typed: strict
# frozen_string_literal: true

module Copilot
  module Businesses
    module ActivityExport
      extend T::Helpers
      include GitHub::Memoizer
      include Copilot::Metrics
      include Copilot::Helpers
      include Copilot::Businesses::Signatures

      include HasActivityExport

      abstract!

      sig { override.returns(T.nilable(String)) }
      def to_activity_csv
        return nil unless activity_seats.count.positive?

        collect_metrics("copilot.to_activity_csv") do
          generate_activity_csv(object_type: object_type)
        end
      end

      sig { override.returns(String) }
      def get_activity_report_filename
        "#{business_object.slug.parameterize}-seat-activity-#{Time.current.to_i}.csv"
      end

      sig { override.returns(T.any(ActiveRecord::Relation, T::Array[Copilot::Seat])) }
      memoize def activity_seats
        Copilot::Activity.activity_seats_for_business(business_object)
      end

      sig { returns(Symbol) }
      memoize def object_type
        copilot_standalone? ? :standalone_business : :business
      end
    end
  end
end
