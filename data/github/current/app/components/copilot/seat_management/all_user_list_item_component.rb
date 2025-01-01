# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class AllUserListItemComponent < ApplicationComponent

      sig { returns(::Organization) }
      attr_reader :organization

      sig { returns(Copilot::Organizations::SeatManagement::Detail) }
      attr_reader :detail

      delegate :assigned_user, :last_activity_at, :pending_cancellation_date, to: :detail

      sig { params(organization: ::Organization, detail: Copilot::Organizations::SeatManagement::Detail).void }
      def initialize(organization, detail)
        @organization = organization
        @detail       = detail
      end

      # This feels nasty. We're rendering Organizations::Settings::MemberAvatarAndProfileLinkComponent which requires a persisted
      # user in order to generate a route. We might want to rethink the default User.new that we set in Copilot::Organizations::SeatManagement::Detail
      sig { returns(T::Boolean) }
      def render?
        assigned_user.persisted?
      end
    end
  end
end
