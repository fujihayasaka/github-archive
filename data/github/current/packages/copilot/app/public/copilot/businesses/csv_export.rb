# typed: strict
# frozen_string_literal: true

module Copilot
  module Businesses
    module CsvExport
      extend T::Helpers
      extend T::Sig
      include GitHub::Memoizer
      include Copilot::Metrics
      include Copilot::Helpers
      include Copilot::Businesses::Signatures

      HEADER = T.let(["Login", "Organizations", "Status", "Last Usage", "Last Editor Used"], T::Array[String])
      STANDALONE_HEADER = T.let(["Login", "Status", "Last Usage", "Last Editor Used"], T::Array[String])

      abstract!

      sig { override.returns(T.nilable(String)) }
      def to_csv
        return nil unless copilot_seats.count.positive?
        GitHub.dogstats.time("copilot.csv_export", tags: ["type:business"]) do
          if copilot_standalone?
            standalone_business_csv
          else
            standard_business_csv
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

      sig { returns(T.nilable(String)) }
      def standard_business_csv
        user_ids, users_to_organizations = load_organization_seats
        users = ::User.where(id: user_ids).pluck(:id, :display_login).to_a
        assignment_data = Copilot::SeatAssignment.joins(:seats).where(organization: copilot_organizations).where("copilot_seats.assigned_user_id IN (?)", user_ids).select("copilot_seat_assignments.pending_cancellation_date, copilot_seats.assigned_user_id, copilot_seat_assignments.assignable_type, copilot_seat_assignments.assignable_id").index_by(&:assigned_user_id)
        usage_data = Copilot::AggregateUsageDetail.where(user_id: user_ids).group(:user_id).select("MAX(updated_at) as updated_at, editor_details, user_id").index_by(&:user_id)

        CSV.generate do |csv|
          csv << HEADER

          users.each do |user|
            assignment_details = assignment_data[user[0]]
            pending_cancellation_date = assignment_details ? assignment_details.pending_cancellation_date : nil
            activity = usage_data[user[0]]
            user_with_organizations = users_to_organizations[user[0]]
            organizations = user_with_organizations ? user_with_organizations.join(", ") : "No organizations"
            last_activity_at = activity ? activity.updated_at : nil
            last_editor_used = activity ? activity.editor_details : nil
            csv << [
              user[1],
              organizations,
              pending_cancellation_date.present? ? "Pending cancellation #{pending_cancellation_date}" : "Active",
              last_activity_at.present? ? last_activity_at.strftime("%Y-%m-%d") : "No activity",
              last_editor_used.present? ? last_editor_used : "No activity",
            ]
          end
        end
      end

      sig { returns(T.nilable(String)) }
      def standalone_business_csv
        user_ids = Copilot::Seat.for_owner(business_object).pluck(:assigned_user_id).uniq
        users = ::User.where(id: user_ids).pluck(:id, :display_login).to_a
        assignment_data = Copilot::SeatAssignment
                            .joins(:seats)
                            .where(owner_type: "Business", owner_id: business_object.id)
                            .where("copilot_seats.assigned_user_id IN (?)", user_ids)
                            .select("copilot_seat_assignments.pending_cancellation_date, copilot_seats.assigned_user_id")
                            .index_by(&:assigned_user_id)
        usage_data = Copilot::AggregateUsageDetail.where(user_id: user_ids).group(:user_id).select("MAX(updated_at) as updated_at, editor_details, user_id").index_by(&:user_id)

        CSV.generate do |csv|
          csv << STANDALONE_HEADER

          users.each do |user|
            assignment_details = assignment_data[user[0]]
            pending_cancellation_date = assignment_details ? assignment_details.pending_cancellation_date : nil
            activity = usage_data[user[0]]
            last_activity_at = activity ? activity.updated_at : nil
            last_editor_used = activity ? activity.editor_details : nil
            csv << [
              user[1],
              pending_cancellation_date.present? ? "Pending cancellation #{pending_cancellation_date}" : "Active",
              last_activity_at.present? ? last_activity_at.strftime("%Y-%m-%d") : "No activity",
              last_editor_used.present? ? last_editor_used : "No activity",
            ]
          end
        end
      end

      sig { returns([T::Set[Integer], T::Hash[Integer, T::Array[String]]]) }
      def load_organization_seats
        user_ids = Set.new
        users_to_organizations = Hash.new

        copilot_organizations.each do |organization|
          org_user_ids = Copilot::Seat.for_organization(organization).pluck(:assigned_user_id)
          org_user_ids.each do |user_id|
            users_to_organizations[user_id] ||= []
            users_to_organizations[user_id] << organization.organization_object.display_login
          end
          user_ids.merge(org_user_ids)
        end

        [user_ids, users_to_organizations]
      end
    end
  end
end
