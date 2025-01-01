# typed: true
# frozen_string_literal: true

class TeamSearchShortcut < ApplicationRecord::Domain::Users
  include GitHub::UTF8
  include GitHub::Prioritizable
  include GitHub::Relay::GlobalIdentification
  include GitHub::Validations
  include Instrumentation::Model
  include SearchDisplayable
  include SearchQueryable
  include SearchPriorityHelper

  MAX_PER_DASHBOARD = 25

  validates :dashboard, presence: true

  belongs_to :dashboard,
    class_name: "TeamDashboard",
    foreign_key: :team_dashboard_id,
    inverse_of: :shortcuts

  # rubocop:todo Rails/InverseOf
  belongs_to :scoping_repository,
    class_name: "Repository",
    foreign_key: :scoping_repository_id
  # rubocop:enable Rails/InverseOf

  delegate :user, :async_user, to: :dashboard

  validate :dashboard_team_has_less_than_max_shortcuts, on: :create
  validate :dashboard_team_can_view_scoping_repository, on: :create
  validates :priority, uniqueness: { scope: :team_dashboard_id, allow_nil: true },
    numericality: {
      less_than_or_equal_to: GitHub::Prioritizable::MAX_PRIORITY_VALUE,
      greater_than_or_equal_to: 0,
      allow_nil: true
    }

  private

  def dashboard_team_has_less_than_max_shortcuts
    if self.class.where(team_dashboard_id: team_dashboard_id).count >= MAX_PER_DASHBOARD
      errors.add(:base, "cannot have more than #{MAX_PER_DASHBOARD} shortcuts")
    end
  end

  def dashboard_team_can_view_scoping_repository
    if scoping_repository && !scoping_repository&.readable_by?(dashboard&.team)
      errors.add(:scoping_repository, :not_found, message: "not found for dashboard owner")
    end
  end
end
