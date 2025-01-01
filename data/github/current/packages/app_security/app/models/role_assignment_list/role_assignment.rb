# typed: strict
# frozen_string_literal: true

module RoleAssignmentList
  class RoleAssignment
    extend T::Sig

    sig { returns(T.any(User, Team)) }
    attr_reader :actor

    sig { returns(Role) }
    attr_reader :role

    sig { returns(T.nilable(Team)) }
    attr_reader :assigned_team

    sig { returns(T.nilable(Team)) }
    attr_reader :through

    sig { params(actor: T.any(User, Team), role: Role, assigned_team: T.nilable(Team), through: T.nilable(Team)).void }
    def initialize(actor: , role:, assigned_team: nil, through: nil)
      @actor = actor
      @role = role
      @assigned_team = assigned_team
      @through = through
    end

    sig { returns(T::Boolean) }
    def direct?
      assigned_team.nil?
    end

    sig { returns(T::Boolean) }
    def indirect?
      !direct?
    end
  end
end
