# typed: true
# frozen_string_literal: true

# A team's dashboard. Represents a Homescreen, or Homepage.
class TeamDashboard < ApplicationRecord::Domain::Users
  include GitHub::Prioritizable::Context
  include GitHub::Tracing

  belongs_to :team

  has_many :shortcuts,
    -> { T.unsafe(self).by_priority },
    class_name: "TeamSearchShortcut",
    foreign_key: :team_dashboard_id,
    inverse_of: :dashboard,
    dependent: :destroy

  prioritizes :shortcuts, with: :shortcuts, inverse_of: :dashboard

  validates :team, presence: true, uniqueness: true

  trace_method :prioritize_dependent!, span_attribute_extractor: -> (context, *args, **kwargs) { context.trace_tags(*args, **kwargs) }

  def global_id
    "#{T.unsafe(team).global_id}:#{id}"
  end
end
