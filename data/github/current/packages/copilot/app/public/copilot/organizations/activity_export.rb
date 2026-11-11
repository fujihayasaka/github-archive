# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module ActivityExport
      extend T::Helpers
      include GitHub::Memoizer
      include Copilot::Metrics
      include Copilot::Helpers
      include Copilot::Organizations::Signatures

      include HasActivityExport

      abstract!

      sig { override.returns(T.nilable(String)) }
      def to_activity_csv
        return nil unless activity_seats.count.positive?

        collect_metrics("copilot.to_activity_csv") do
          generate_activity_csv(object_type: :organization)
        end
      end

      sig { override.returns(String) }
      def get_activity_report_filename
        "#{organization_object.display_login.parameterize}-seat-activity-#{Time.current.to_i}.csv"
      end

      sig { override.returns(T.any(ActiveRecord::Relation, T::Array[Copilot::Seat])) }
      memoize def activity_seats
        GitHub.dogstats.time("copilot.activity_export.seat_load", tags: ["type:organization"]) do
          Copilot::Seat.without_access_revoked(owner: organization_object)
        end
      end
    end
  end
end
