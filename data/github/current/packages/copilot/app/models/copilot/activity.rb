# typed: strict
# frozen_string_literal: true

module Copilot
  class Activity < ApplicationRecord::Copilot
    # NOTE
    # Writes to this table take place in the github/copilot-activity-service repo.

    include ::Instrumentation::Model
    include Copilot::Helpers

    self.table_name = "copilot_activities"
    self.strict_loading_by_default = true

    # rubocop:todo Rails/InverseOf
    belongs_to :seat, class_name: "Copilot::Seat", foreign_key: :copilot_seat_id, strict_loading: false
    # rubocop:enable Rails/InverseOf

    # Maximum number of seat ids per `copilot_activities` query. Per DBA
    # guidance we avoid large `IN (...)` lists, so pages above this threshold
    # are split into `ceil(page_size / IDS_PER_QUERY)` queries. Matches the
    # `each_slice(500)` convention used elsewhere in the monolith.
    IDS_PER_QUERY = T.let(500, Integer)

    sig { params(seat: Copilot::Seat).returns(T.nilable(Copilot::Activity)) }
    def self.for_seat(seat)
      find_by(copilot_seat_id: seat.id)
    end

    sig { params(seats: T::Enumerable[Copilot::Seat]).returns(T::Array[Copilot::Activity]) }
    def self.for_seats(seats)
      # No join through seat_assignment so this matches `for_seat` semantics,
      # including seats whose seat assignment has been destroyed. The unique
      # index on copilot_seat_id guarantees at most one activity per seat.
      # Ids are de-duplicated and chunked into IDS_PER_QUERY-sized batches per
      # DBA guidance; .uniq preserves the prior single-IN-list set semantics.
      ids = seats.map(&:id).uniq
      return [] if ids.empty?

      ids.each_slice(IDS_PER_QUERY).flat_map do |id_chunk|
        where(copilot_seat_id: id_chunk).to_a
      end
    end

    sig { params(organization: ::Organization).returns(ActiveRecord::Relation) }
    def self.for_organization(organization)
      joins(seat: :seat_assignment).where(copilot_seat_assignments: { owner_type: "Organization", owner_id: organization.id })
    end

    sig { params(business: ::Business).returns(ActiveRecord::Relation) }
    def self.for_business(business)
      activity_seats = activity_seats_for_business(business)
      where(seat: activity_seats)
    end

    sig { params(user: ::User).returns(T.nilable(Copilot::Activity)) }
    def self.latest_for_user(user)
      joins(:seat).where(copilot_seats: { assigned_user_id: user.id }).order(activity_at: :desc).first
    end

    sig { returns(String) }
    def last_surface_used
      return activity_details if activity_details.present?
      return activity_source if activity_source.present?

      "Unspecified surface"
    end

    sig { params(business: ::Business).returns(T::Array[Copilot::Seat]) }
    def self.activity_seats_for_business(business)
      copilot_business = Copilot::Business.new(business)
      biz_type = copilot_business.copilot_standalone? ? "standalone_business" : "business"

      GitHub.dogstats.time("copilot.activity.seat_load", tags: ["type:#{biz_type}"]) do
        # if this is a standalone business, we only want to return the seats for the business
        return Copilot::Seat.without_access_revoked(owner: business).to_a if copilot_business.copilot_standalone?

        # otherwise, we need to get all of the organizations for the business
        organization_ids = business.organizations.pluck(:id)

        seats = Copilot::Seat.joins(:seat_assignment).where(copilot_seat_assignments: { owner_id: organization_ids, owner_type: "Organization", access_revoked_at: nil }).to_a
        seats += Copilot::Seat.business_owned(business).where(copilot_seat_assignments: { access_revoked_at: nil }).to_a if business.can_assign_copilot_to_business_users?
        seats.uniq
      end
    end
  end
end
