# typed: strict
# frozen_string_literal: true
class EnterpriseTeamAssignment < ApplicationRecord::Domain::Users
  extend T::Sig
  include Instrumentation::Model

  VALID_TYPES = %(copilot security_manager)

  belongs_to :enterprise_team

  validates_presence_of :enterprise_team, message: "Team is required"
  validates_presence_of :assignment_type, message: "Assigment type is required"
  validates_inclusion_of :assignment_type, in: VALID_TYPES, message: "Invalid assignment type"
  validates_uniqueness_of :enterprise_team_id, scope: :assignment_type, message: "Assignment type already exists for the team"

  after_commit :emit_assignment, on: :create, unless: :skip_event_emissions
  after_commit :emit_unassignment, on: :destroy, unless: :skip_event_emissions

  sig { returns(T.nilable(T::Boolean)) }
  attr_accessor :skip_event_emissions

  sig { void }
  def emit_assignment
    instrument "#{assignment_type}_assignment",
      business_id: enterprise_team&.business_id,
      business: enterprise_team&.business,
      enterprise_team_id: enterprise_team_id,
      enterprise_team: enterprise_team&.slug,
      prefix: enterprise_team&.event_prefix

    instrument :assignment,
      id: enterprise_team_id,
      prefix: EnterpriseTeam.assignment_event_prefix(assignment_type)
  end

  sig { void }
  def emit_unassignment
    # Assignments are deleted in the background after the team is deleted, so we have special logic in EnterpriseTeam after_commit to emit this event synchronously to maintain reliability even if the background job fails
    # this check stops us from emitting the event twice
    return if enterprise_team.nil?
    instrument "#{assignment_type}_unassignment",
      business_id: enterprise_team&.business_id,
      business: enterprise_team&.business,
      enterprise_team_id: enterprise_team_id,
      enterprise_team: enterprise_team&.slug,
      prefix: enterprise_team&.event_prefix

    instrument :unassignment,
      id: enterprise_team_id,
      prefix: EnterpriseTeam.assignment_event_prefix(assignment_type)
  end
end
