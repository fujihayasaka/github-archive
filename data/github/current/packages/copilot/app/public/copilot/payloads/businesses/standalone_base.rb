# typed: strict
# frozen_string_literal: true

module Copilot
  module Payloads
    module Businesses
      class StandaloneBase
        extend T::Sig
        extend T::Helpers
        include GitHub::Memoizer
        abstract!

        PER_PAGE = 25

        SeatAssignmentWithStatus = T.type_alias do
          {
            entity: T.any(Copilot::SeatAssignment, EnterpriseTeamAssignment, EnterpriseTeam),
            status: Copilot::Types::SeatAssignment::Status
          }
        end

        sig { returns(::Business) }
        attr_reader :business

        sig { returns(ActionController::Parameters) }
        attr_reader :params

        sig { params(business: ::Business, params: ActionController::Parameters).void }
        def initialize(business:, params:)
          @business = business
          @params = params
        end

        sig { abstract.returns(T.untyped) } # rubocop:disable Sorbet/ForbidTUntyped
        def call; end
        # Any payload builder inheriting from this class should implement a call method that returns the final payload
        # There are a few methods that are particularly relevant to any subclass of this class:
        # - all_assignments: returns all the seat assignments and enterprise team assignments for the business
        # - filtered_assignments: returns the assignments that match the search query, sorted by the sort param
        # - paginated_assignments: returns the filtered assignments that are on the given page

        private

        sig { returns(T::Array[SeatAssignmentWithStatus]) }
        memoize def all_assignments
          assignments_with_status
        end

        sig { returns(T::Array[SeatAssignmentWithStatus]) }
        memoize def filtered_assignments
          sorted_assignments
        end

        sig { returns(T::Array[SeatAssignmentWithStatus]) }
        memoize def paginated_assignments
          page = (params[:page] || 1).to_i
          sorted_assignments.slice((page - 1) * PER_PAGE, PER_PAGE) || []
        end

        sig { returns(T::Array[SeatAssignmentWithStatus]) }
        memoize def sorted_assignments
          case params[:sort]
          when "name_desc"
            searched_assignments.sort_by { |assignment| assignable_from(assignment[:entity]).name.downcase }.reverse
          when "member_count_asc"
            searched_assignments.sort_by { |assignment| assignable_from(assignment[:entity]).member_count }
          when "member_count_desc"
            searched_assignments.sort_by { |assignment| assignable_from(assignment[:entity]).member_count }.reverse
          else
            # Set the default sort to name_asc
            searched_assignments.sort_by { |assignment| assignable_from(assignment[:entity]).name.downcase }
          end
        end

        sig { returns(T::Array[SeatAssignmentWithStatus]) }
        memoize def searched_assignments
          return all_assignments unless params[:q].present?

          query = params[:q].downcase

          all_assignments.filter do |assignment|
            assignable = assignable_from(assignment[:entity])
            assignment if assignable.name.include?(query) || assignable.slug.include?(query)
          end
        end

        sig { returns(T::Array[Copilot::SeatAssignment]) }
        memoize def seat_assignments
          Copilot::SeatAssignment.for_standalone_business(business)
        end

        sig { returns(ActiveRecord::Relation) }
        memoize def enterprise_team_assignments
          T.unsafe(EnterpriseTeamAssignment)
            .includes(enterprise_team: { enterprise_team_group_mappings: :external_group })
            .joins(:enterprise_team)
            .where(enterprise_team: { business_id: business.id })
            .where(assignment_type: "copilot")
        end

        sig { returns(T::Array[SeatAssignmentWithStatus]) }
        memoize def assignments_with_status
          indexed_seat_assignments = T.cast(seat_assignments.index_by(&:assignable_id),
                                            T::Hash[Integer, Copilot::SeatAssignment])
          indexed_ent_team_assignments = T.cast(enterprise_team_assignments.index_by(&:enterprise_team_id),
                                                T::Hash[Integer, Copilot::SeatAssignment])

          # Because operations happen to seat assignments as a part of async jobs, we have to manually
          # decorate the assignments with temporary status data to give users the feedback that _something_
          # is happening to these objects.
          result = (indexed_seat_assignments.keys | indexed_ent_team_assignments.keys).map do |key|
            # Both a seat assignment AND a corresponding enterprise team assignment are present.
            if indexed_seat_assignments.key?(key) && indexed_ent_team_assignments.key?(key)
              entity = T.must(indexed_seat_assignments[key])
              status = entity.pending_cancellation_date.present? ? get_enum_field("Reassigning") : get_enum_field("Stable")
            # SeatAssignment is present, EnterpriseTeamAssignment is not
            elsif indexed_seat_assignments.key?(key) && !indexed_ent_team_assignments.key?(key)
              entity = T.must(indexed_seat_assignments[key])
              status = entity.pending_cancellation_date.present? ? get_enum_field("Cancelling") : get_enum_field("Unassigning")
            # If we have an enterprise team and no assignment, that means we are creating a seat assignment.
            elsif indexed_ent_team_assignments.key?(key) && !indexed_seat_assignments.key?(key)
              entity = indexed_ent_team_assignments[key]
              status = get_enum_field("Creating")
            end

            if entity.nil? || status.nil?
              # there didn't seem to be either of the objects we were expecting
              nil
            else
              {
                entity: entity,
                status: T.let(status, Copilot::Types::SeatAssignment::Status),
              }
            end
          end.compact

          result
        end

        sig { params(assignment: SeatAssignmentWithStatus).returns(Copilot::Types::EnterpriseTeamAssignmentPayload) }
        def serialized_assignment(assignment)
          assignable = assignable_from(assignment[:entity])

          serialized = {
            id: T.let(nil, T.nilable(Integer)),
            assignable_type: "EnterpriseTeam",
            pending_cancellation_date: T.let(nil, T.nilable(Date)),
            last_activity_at: Copilot::AggregateUsageDetail.latest_for_users(assignable.member_user_ids)&.updated_at&.iso8601,
            status: assignment[:status].serialize,
            assignable: serialized_team(assignable)
          }

          if assignment[:entity].is_a?(Copilot::SeatAssignment)
            serialized[:id] = assignment[:entity].id
            serialized[:pending_cancellation_date] = assignment[:entity].pending_cancellation_date
          end

          serialized
        end

        sig { params(team: ::EnterpriseTeam).returns(Copilot::Types::EnterpriseTeamAssignablePayload) }
        def serialized_team(team)
          {
            id: T.must(team.id),
            slug: team.slug,
            login: team.name,
            member_count: team.member_count,
            mapping_id: T.cast(team.enterprise_team_group_mappings.first, T.nilable(EnterpriseTeamGroupMapping))&.external_group&.id,
            member_ids: team.member_user_ids
          }
        end

        sig { params(assignment: T.any(Copilot::SeatAssignment, EnterpriseTeamAssignment, EnterpriseTeam)).returns(::EnterpriseTeam) }
        def assignable_from(assignment)
          if assignment.is_a?(Copilot::SeatAssignment)
            T.cast(assignment.assignable, EnterpriseTeam)
          elsif assignment.is_a?(EnterpriseTeamAssignment)
            T.must(assignment.enterprise_team)
          else
            assignment
          end
        end

        sig { params(enum_field: String).returns(Copilot::Types::SeatAssignment::Status) }
        def get_enum_field(enum_field)
          Copilot::Types::SeatAssignment::Status.const_get(enum_field)
        end
      end
    end
  end
end
