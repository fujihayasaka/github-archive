# typed: true
# frozen_string_literal: true

class SponsorsGoalContribution < ApplicationRecord::Domain::Sponsors
  # rubocop:todo Rails/InverseOf
  belongs_to :goal,
    required: true,
    class_name: :SponsorsGoal,
    foreign_key: :sponsors_goal_id
  # rubocop:enable Rails/InverseOf

  # rubocop:todo Rails/InverseOf
  belongs_to :tier,
    required: true,
    class_name: :SponsorsTier,
    foreign_key: :sponsors_tier_id
  # rubocop:enable Rails/InverseOf

  belongs_to :sponsor,
    required: true,
    class_name: :User
end
