# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module SeatManagement
      class Detail
        include GitHub::Memoizer

        sig { returns(Copilot::SeatAssignment) }
        attr_reader :seat_assignment

        sig { returns(::User) }
        attr_reader :assigned_user

        sig { returns(T::Boolean) }
        def has_assigned_user?
          @assigned_user.persisted?
        end

        sig { returns(Integer) }
        attr_reader :seat_assignment_id

        sig { returns(Time) }
        attr_reader :last_activity_at

        sig { returns(T.nilable(OrganizationAssignable)) }
        attr_reader :assignable

        sig { returns(T.any(T.nilable(DateTime), T.nilable(Date))) }
        attr_reader :pending_cancellation_date

        sig { returns(T.any(T.nilable(DateTime), T.nilable(Date), T.nilable(ActiveSupport::TimeWithZone))) }
        attr_reader :access_revoked_at

        sig do
          params(organization: ::Organization,
            seat_assignment: Copilot::SeatAssignment,
            assignable: T.nilable(OrganizationAssignable),
            pending_cancellation_date: T.any(T.nilable(DateTime), T.nilable(Date)),
            last_activity_at: T.nilable(Time),
            assigned_user: ::User,
            access_revoked_at: T.any(T.nilable(DateTime), T.nilable(Date), T.nilable(ActiveSupport::TimeWithZone)),
          ).void
        end
        def initialize(
          organization:,
          seat_assignment:,
          assignable:,
          pending_cancellation_date:,
          last_activity_at:,
          assigned_user: ::User.new,
          access_revoked_at: nil
        )
          @organization              = organization
          @seat_assignment           = seat_assignment
          @seat_assignment_id        = T.let(seat_assignment.id.nil? ? 0 : seat_assignment.id, Integer)
          @last_activity_at          = T.let(last_activity_at.present? ? last_activity_at : Time.at(0), Time)
          @assignable                = assignable
          @pending_cancellation_date = pending_cancellation_date
          @assigned_user             = assigned_user
          @access_revoked_at         = access_revoked_at
        end

        sig { returns(String) }
        memoize def sortable_name
          case assignable
          when ::Team
            team = T.cast(assignable, ::Team)
            "#{team.slug} #{team.members.map(&:display_login).sort.join(' ')}"
          when ::OrganizationInvitation
            invitation = T.cast(assignable, ::OrganizationInvitation)
            return T.must(invitation.invitee).login.to_s if invitation.invitee.present?
            invitation.email.to_s
          when ::User
            T.cast(assignable, ::User).login.to_s
          else
            ""
          end
        end

        alias :to_s :sortable_name
      end
    end
  end
end
