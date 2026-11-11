# typed: strict
# frozen_string_literal: true

class EnterpriseTeamMigration < ApplicationRecord::Domain::Accounts
  belongs_to :enterprise_team, inverse_of: :enterprise_team_migration
  belongs_to :business_team, foreign_key: :team_id, inverse_of: :enterprise_team_migration

  enum :migration_status, {
    in_progress: 0,
    completed: 1,
    failed: 2,
    dual_write: 3
  }, default: :in_progress, validate: true

  validates :enterprise_team_id, presence: true, uniqueness: true
  validates :team_id, presence: true, uniqueness: true
  validates :migration_status, presence: true

  sig { params(enterprise_team: EnterpriseTeam).returns(EnterpriseTeamMigration) }
  def self.start!(enterprise_team)
    business = T.must(enterprise_team.business)
    return T.must(enterprise_team.enterprise_team_migration) unless enterprise_team.enterprise_team_migration.nil?
    mappings = enterprise_team.enterprise_team_group_mappings.includes(external_group: :provider)
    business_team = T.let(nil, T.nilable(BusinessTeam))
    migration = with_write do
      business_team = business.business_teams.create(name: enterprise_team.name, organization_selection_type: :disabled)
      mappings.each do |mapping|
        ExternalGroupTeam.create!(team_id: business_team.id, external_group_id: mapping.external_group_id)
      end
      enterprise_team.create_enterprise_team_migration(business_team: business_team)
    end
    if assignment = Copilot::SeatAssignment.for_enterprise_team(enterprise_team).first
      create_business_team_seat_assignment!(T.must(business_team), business, T.must(assignment.assigning_user))
    elsif enterprise_team.copilot_enterprise_team?
      create_business_team_seat_assignment!(T.must(business_team), business, business.owners.first)
    end
    migration
  rescue => e
    if business_team.present?
      Copilot::SeatAssignment.with_write do
        Copilot::SeatAssignment.for_business_team_id(business_team.id).destroy_all
      end
      with_write { business_team.destroy }
    end
    with_write { migration.destroy } if migration.present?
    raise e
  end

  sig { void }
  def completed_cleanup!
    return if !completed? && !dual_write?

    old_team = T.must(enterprise_team)
    repoint_copilot_seats!(old_team)
    with_write do
      update!(migration_status: :completed)
      old_team.destroy!
      destroy!
    end
  end

  sig { void }
  def reset!
    return if completed?

    with_write do
      Copilot::SeatAssignment.for_business_team_id(team_id).destroy_all
      T.must(business_team).destroy!
      destroy!
    end
  end

  sig { void }
  def perform_initial_sync
    sync_team
    sync_memberships
    with_write { update(migration_status: :dual_write) }
  end

  sig { void }
  def sync_team
    with_write { T.must(business_team).update(name: T.must(enterprise_team).name) }
  end

  sig { void }
  def destroy_team
    with_write { T.must(business_team).destroy }
  end

  sig { void }
  def sync_memberships
    users = User.where(id: T.must(enterprise_team).member_user_ids - T.must(business_team).member_ids).to_a
    with_write { T.must(business_team).bulk_add_members(users, caller_type: :business_team, skip_feature_check: true) } if users.any?
  end

  sig { params(membership: EnterpriseTeamMembership).void }
  def create_membership(membership)
    return unless business_team.present?
    T.must(business_team).add_member(T.must(membership.user), caller_type: :business_team, skip_feature_check: true)
  end

  sig { params(membership: EnterpriseTeamMembership).void }
  def destroy_membership(membership)
    return if !business_team.present?
    if membership.user.present?
      T.must(business_team).remove_member(T.must(membership.user), caller_type: :business_team)
    else
      Ability.where(subject: T.must(business_team), actor_id: membership.user_id, actor_type: "User").destroy_all
    end
  end

  sig { params(assignment: EnterpriseTeamAssignment).void }
  def create_assignment(assignment)
    business_team = T.must(self.business_team)
    return if Copilot::SeatAssignment.for_business_team(business_team).exists?

    business = T.must(business_team.business)
    owner = business.owners.first
    return unless owner
    self.class.create_business_team_seat_assignment!(business_team, business, owner)
  end

  sig { params(assignment: EnterpriseTeamAssignment).void }
  def destroy_assignment(assignment)
    Copilot::SeatAssignment.for_business_team_id(team_id).destroy_all
  end

  sig { returns(T::Boolean) }
  def dual_write_enabled?
    dual_write?
  end

  sig { params(business_team: BusinessTeam, business: Business, assigning_user: User).returns(Copilot::SeatAssignment) }
  def self.create_business_team_seat_assignment!(business_team, business, assigning_user)
    new_assignment = Copilot::SeatAssignment.new(
      owner: business,
      assignable: business_team,
      assigning_user: assigning_user,
    )
    new_assignment.skip_delayed_converter_job = true
    Copilot::SeatAssignment.with_write { new_assignment.save! }
    new_assignment
  rescue ActiveRecord::ActiveRecordError => e
    GitHub.logger.error(
      "Failed to create Copilot::SeatAssignment for BusinessTeam during enterprise team migration",
      "exception" => e,
      "gh.business.id" => business.id,
      "gh.business_team.id" => business_team.id,
    )
    raise
  end

  sig { params(enterprise_team: EnterpriseTeam).void }
  def repoint_copilot_seats!(enterprise_team)
    enterprise_team_assignment = Copilot::SeatAssignment.for_enterprise_team(enterprise_team).first
    business_team_assignment = Copilot::SeatAssignment.for_business_team(business_team).first
    return unless enterprise_team_assignment && business_team_assignment
    return unless enterprise_team_assignment.seats.exists?

    with_write do
      enterprise_team_assignment.seats.update_all(
        copilot_seat_assignment_id: business_team_assignment.id,
        updated_at: Time.current,
      )
    end
  end

  sig { params(enterprise_team: EnterpriseTeam).void }
  def unrepoint_copilot_seats!(enterprise_team)
    enterprise_team_assignment = Copilot::SeatAssignment.for_enterprise_team(enterprise_team).first
    business_team_assignment = Copilot::SeatAssignment.for_business_team(business_team).first
    return unless enterprise_team_assignment && business_team_assignment
    return unless business_team_assignment.seats.exists?

    with_write do
      business_team_assignment.seats.update_all(
        copilot_seat_assignment_id: enterprise_team_assignment.id,
        updated_at: Time.current,
      )
    end
  end
end
