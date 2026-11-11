# typed: strict
# frozen_string_literal: true

module Stafftools
  module Businesses
    class CopilotStandaloneSeatsController < Stafftools::Businesses::BusinessBaseController
      include GitHub::Memoizer

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Ballast,
        ApplicationRecord::Billing,
        ApplicationRecord::Collab,
        ApplicationRecord::Copilot,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Repositories,
        ApplicationRecord::IssuesPullRequests,
        only: [:show]

      sig { void }
      def show
        copilot_seat_assignments = ::Copilot::SeatAssignment
          .where(owner_id: this_business.id, assignable_type: "EnterpriseTeam")

        query = params[:query] || ""
        user_ids = ::Copilot::Seat.for_business(this_business).pluck(:assigned_user_id)

        if params[:query].present?
          user_ids = ::User.where(id: user_ids).where("login LIKE ?", "%#{query}%").pluck(:id)
        end

        copilot_seats = ::Copilot::Seat.joins(:seat_assignment).
          where(copilot_seat_assignments: { owner: this_business }).
          where(assigned_user_id: user_ids).
          paginate(page: params[:page] || 1, per_page: 10)

        render "stafftools/businesses/copilot/standalone_seats", locals: {
          copilot_business: ::Copilot::Business.new(this_business),
          copilot_seats: copilot_seats,
        }
      end
    end
  end
end
