# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module CsvExport
      extend T::Helpers
      include GitHub::Memoizer
      include Copilot::Metrics
      include Copilot::Helpers
      include Copilot::Organizations::Signatures

      HEADER = T.let(["Login", "Status", "Team", "Last Usage Date", "Last Editor Used"], T::Array[String])

      abstract!

      sig { override.returns(T.nilable(String)) }
      def to_csv
        return nil unless has_assigned_seats?

        GitHub.dogstats.time("copilot.csv_export", tags: ["type:organization"]) do
          # so, we've got us some assigned seats. let's do that iteration thing.
          CSV.generate do |csv|
            csv << HEADER
            load_assignment_details(csv)
          end
        end
      end

      sig do
        abstract.type_parameters(:A).params(
          name: String,
          tags: T::Hash[Symbol, String],
          block: T.proc.returns(T.type_parameter(:A)),
        ).returns(T.type_parameter(:A))
      end
      def collect_metrics(name, **tags, &block); end

      private

      sig { params(csv: CSV).returns(CSV) }
      def load_assignment_details(csv)
        collect_metrics("copilot.csv_export.load_assignment_details") do
          users.each do |user|
            assignment_details = assignment_data[user[0]]
            pending_cancellation_date = assignment_details ? assignment_details.pending_cancellation_date : nil
            activity = usage_data[user[0]]

            last_activity_at = nil
            last_editor_used = nil
            case activity
            when Copilot::Activity
              last_activity_at = activity.activity_at
              last_editor_used = activity.activity_details
            when Copilot::AggregateUsageDetail
              last_activity_at = activity.updated_at
              last_editor_used = activity.editor_details
            end

            csv << [
              user[1],
              pending_cancellation_date.present? ? "Pending cancellation #{pending_cancellation_date}" : "Active",
              teams[T.must(assignment_details).assignable_id].present? ? T.must(teams[T.must(assignment_details).assignable_id]).name : "No team",
              last_activity_at.present? ? last_activity_at.strftime("%Y-%m-%d") : "No activity",
              last_editor_used.present? ? last_editor_used : "No activity",
            ]
          end
          csv
        end
      end

      sig { returns(T::Hash[Integer, ::Team]) }
      memoize def teams
        collect_metrics("copilot.csv_export.teams_load") do
          organization_object.teams.select(:id, :name).index_by(&:id)
        end
      end

      sig { returns(T::Array[Integer]) }
      memoize def user_ids
        collect_metrics("copilot.csv_export.user_ids_load") do
          Copilot::Seat.for_organization(organization_object).pluck(:assigned_user_id)
        end
      end

      sig { returns(T::Array[::User]) }
      memoize def users
        collect_metrics("copilot.csv_export.users_load") do
          ::User.where(id: user_ids).pluck(:id, :display_login).to_a
        end
      end

      sig { returns(T::Hash[Integer, T.any(Copilot::AggregateUsageDetail, Copilot::Activity)]) }
      memoize def usage_data
        collect_metrics("copilot.csv_export.usage_data") do
          if FeatureFlag.vexi.enabled?(:copilot_use_activity_for_csv_export, organization_object, default: false) || FeatureFlag.vexi.enabled?(:copilot_use_activity_for_csv_export, organization_object.business, default: false)
            Copilot::Activity.for_organization(organization_object).includes(:seat).index_by { |activity| activity.seat.assigned_user_id }
          else
            Copilot::AggregateUsageDetail.where(user_id: user_ids).
              group(:user_id).
              select("MAX(updated_at) as updated_at, editor_details, user_id").
              index_by(&:user_id)
          end
        end
      end

      sig { returns(T::Hash[Integer, Copilot::SeatAssignment]) }
      memoize def assignment_data
        collect_metrics("copilot.csv_export.assignment_data") do
          Copilot::SeatAssignment.joins(:seats).where(organization: organization_object).
            where("copilot_seats.assigned_user_id IN (?)", user_ids).
            select("copilot_seat_assignments.pending_cancellation_date, copilot_seats.assigned_user_id, copilot_seat_assignments.assignable_type, copilot_seat_assignments.assignable_id").
            index_by(&:assigned_user_id)
        end
      end
    end
  end
end
