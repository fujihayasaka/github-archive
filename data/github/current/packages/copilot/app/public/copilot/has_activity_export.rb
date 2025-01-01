# typed: strict
# frozen_string_literal: true

module Copilot
  module HasActivityExport
    extend T::Helpers

    abstract!

    include GitHub::Memoizer
    include Copilot::Helpers

    ACTIVITY_HEADER = T.let(["Report Time", "Login", "Last Authenticated At", "Last Activity At", "Last Surface Used"], T::Array[String])
    HAS_ORGANIZATION_ACTIVITY_HEADER = T.let(["Report Time", "Login", "Last Authenticated At", "Last Activity At", "Last Surface Used", "Organization"], T::Array[String])

    sig { returns(String) }
    def get_activity_report_filename
      Kernel.raise NotImplementedError, "Must be implemented by including class"
    end

    sig { params(object_type: Symbol).returns(T.nilable(String)) }
    def generate_activity_csv(object_type: :unknown)
      return nil if object_type == :unknown

      GitHub.dogstats.distribution_time("copilot.generate_activity_csv", tags: ["object_type:#{object_type}"]) do
        report_time = Time.now.utc.iso8601
        CSV.generate do |csv|
          if object_type == :business
            csv << HAS_ORGANIZATION_ACTIVITY_HEADER
          else
            csv << ACTIVITY_HEADER
          end

          activity_seats.each do |seat|
            seat_id = seat.id
            user_id = seat.assigned_user_id

            user_login = seat_users.fetch(user_id, [])[1] # Fetch the display_login for the user_id
            next unless user_login

            activity = activities.fetch(seat_id, nil)
            authentication = authentications.fetch(seat_id, nil)

            last_activity_at = activity ? activity.activity_at : nil
            last_authenticated_at = authentication ? authentication.authentication_at : nil

            row = [
              report_time,
              user_login,
              last_authenticated_at ? last_authenticated_at.utc.iso8601 : "None",
              last_activity_at ? last_activity_at.utc.iso8601 : "None",
              last_surface_used(activity),
            ]
            row << seat&.seat_assignment&.owner&.name if object_type == :business

            csv << row
          end
        end
      end
    end

    sig do
      params(
        activity: T.nilable(Copilot::Activity),
      ).returns(String)
    end
    def last_surface_used(activity)
      return "None" unless activity

      activity.last_surface_used
    end

    sig { overridable.returns(T.any(ActiveRecord::Relation, T::Array[Copilot::Seat])) }
    memoize def activity_seats
      Kernel.raise NotImplementedError, "Must be implemented by including class"
    end

    sig { returns(T::Hash[Integer, T::Hash[Integer, String]]) }
    memoize def seat_users
      GitHub.dogstats.time("copilot.activity_export.user_load", tags: ["type:organization"]) do
        ::User.where(id: activity_seats.pluck(:assigned_user_id).uniq).pluck(:id, :display_login).index_by(&:first)
      end
    end

    sig { returns(T::Hash[Integer, Copilot::Activity]) }
    memoize def activities
      GitHub.dogstats.time("copilot.activity_export.activity_load", tags: ["type:organization"]) do
        Copilot::Activity.where(seat: activity_seats).index_by(&:copilot_seat_id)
      end
    end

    sig { returns(T::Hash[Integer, Copilot::Authentication]) }
    memoize def authentications
      GitHub.dogstats.time("copilot.activity_export.authentication_load", tags: ["type:organization"]) do
        Copilot::Authentication.where(seat: activity_seats).index_by(&:copilot_seat_id)
      end
    end
  end
end
