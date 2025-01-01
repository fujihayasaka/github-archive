# typed: strict
# frozen_string_literal: true

module Copilot
  module Businesses
    module SeatManagement
      extend T::Helpers

      include Copilot::Helpers
      include Copilot::Businesses::Signatures
      include GitHub::Memoizer

      abstract!

      # Currently, this method only takes teams into account
      sig { params(biz: ::Business).returns(Integer) }
      def self.copilot_standalone_seat_count(biz)
        return 0 unless Copilot::Business.new(biz).copilot_standalone?

        # There really shouldn't be seat assignments with a nil assignable, but we do see them
        # in the current production envrioment. Probably due to the way we've been manually assigning
        # seat assignments for enterprise teams belonging to standalone businesses.
        assignments = Copilot::SeatAssignment.for_standalone_business(biz)
        assignments.map(&:assignable).compact.flat_map(&:member_user_ids).uniq.size
      end

      sig { params(assignables: T::Array[T.any(EnterpriseTeam, BusinessTeam, ::User)], assigning_user: ::User).returns(GitHub::Result) }
      def assign(assignables, assigning_user)
        GitHub::Result.new do
          assignables.map do |assignable|
            result = assigner.assign(assignable, assigning_user)

            Kernel.raise result.error unless result.ok?
            result.value!
          end
        end
      end

      sig { params(assignables: T::Array[T.any(EnterpriseTeam, ::User)], unassigning_user: ::User).returns(GitHub::Result) }
      def unassign(assignables, unassigning_user)
        GitHub::Result.new do
          assignables.map do |assignable|
            result = assigner.unassign(assignable, unassigning_user)

            Kernel.raise result.error unless result.ok?
            result.value!
          end
        end
      end

      private

      sig { returns(Copilot::SeatManagement::Assigner) }
      def assigner
        Copilot::SeatManagement::Assigner.new(business_object)
      end
    end
  end
end
