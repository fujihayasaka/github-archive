# typed: strict
# frozen_string_literal: true

class EnterpriseTeamMembership < ApplicationRecord::Domain::Users
  include Instrumentation::Model

  belongs_to :enterprise_team
  belongs_to :user, inverse_of: :enterprise_team_memberships # rubocop:disable GitHub/UseBelongsToDomain

  validates_presence_of :enterprise_team, :user
  validates_uniqueness_of :enterprise_team, scope: :user, message: "This user is already part of the enterprise team"
  validate :enterprise_team_limit_can_add_more_members, on: :create

  after_commit :instrument_team_update, on: [:create, :destroy]
  after_commit :instrument_add_member, on: [:create]
  after_commit :instrument_remove_member, on: [:destroy]
  after_commit :migration_dual_write_create, on: [:create]
  before_commit :migration_dual_write_destroy, on: [:destroy]

  sig { void }
  def instrument_team_update
    enterprise_team = self.enterprise_team

    # Prevent update events from firing while team being destroyed or being switched to using an IDP, we don't want dozen thousands of updates
    # team destroy is a single unassignment event
    # switching to IDP is a single update event from the IDP logic
    return if enterprise_team.nil?
    return unless enterprise_team.direct_memberships_enabled?

    enterprise_team.instrument_update
  end

  sig { void }
  def instrument_add_member
    enterprise_team = self.enterprise_team
    user = self.user
    return if enterprise_team.nil? || user.nil?

    enterprise_team.instrument_add_member(user)
  end

  sig { void }
  def instrument_remove_member
    enterprise_team = self.enterprise_team
    user = self.user
    return if enterprise_team.nil? || user.nil?

    enterprise_team.instrument_remove_member(user)
  end

  sig { returns(String) }
  def members_limit_reached_message
    T.must(enterprise_team).members_limit_reached_message
  end

  sig { void }
  private def enterprise_team_limit_can_add_more_members
    errors.add(:enterprise_team, members_limit_reached_message) if T.must(enterprise_team).members_limit_reached?
  end

  sig { void }
  private def migration_dual_write_create
    return unless T.must(enterprise_team).write_migration_business_team?
    T.must(enterprise_team).enterprise_team_migration&.create_membership(self)
  end

  sig { void }
  private def migration_dual_write_destroy
    return unless enterprise_team&.write_migration_business_team?
    T.must(enterprise_team).enterprise_team_migration&.destroy_membership(self)
  end
end
