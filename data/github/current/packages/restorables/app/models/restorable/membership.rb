# typed: false
# frozen_string_literal: true

# Internal: Belongs to a Restorable and stores the membership (aka ability)
# details between a user and organizations, teams, and repositories. The user
# association is stored on a Restorable scenario class like
# Restorable::OrganizationUser.
#
# Usage:
#
#  > org = Organization.find_by_login("github")
#  > user = User.find_by_login("jonmagic")
#  > direct_memberships = org.user_direct_abilities_for_organization_teams_and_repositories(user)
#  > restorable = Restorable.create
#
#  > Restorable::Membership.backup(:restorable => restorable, :memberships => direct_memberships)
#  > Restorable::Membership.restore(:restorable => restorable, :user => user)
#
# This class and all of it's methods should only ever be used by other
# Restorable classes and specifically Restorable scenario classes/models like
# Restorable::OrganizationUser.
class Restorable
  class Membership < ApplicationRecord::Domain::Restorables

    # A set of common restorable type model helper methods.
    extend TypeHelpers

    belongs_to :restorable
    # polymorphic relationship will not work on subject_type => "Organization"
    # because there is no organizations table for rails to look for
    belongs_to :subject, polymorphic: true

    scope :organization_memberships, -> { where(subject_type: "Organization") }
    scope :team_memberships, -> { where(subject_type: "Team") }
    scope :repository_memberships, -> { where(subject_type: "Repository") }
    scope :team_and_repo_memberships, -> { where(subject_type: %w[Team Repository]) }

    validates_presence_of :restorable_id, :subject_type, :subject_id, :action
    validates_uniqueness_of :restorable_id, scope: [:subject_type, :subject_id]

    enum :action, Ability.actions

    # Internal: Create a set of membership records.
    #
    # restorable - Restorable parent instance.
    # memberships - An Array of direct membership Abilities.
    def self.backup(restorable:, memberships:)
      save_models(restorable, memberships)
    end

    # Internal: Restore memberships for this user.
    #
    # restorable - Restorable parent instance.
    # user - User instance.
    def self.restore(restorable:, user:, actor:)
      restorable.restoring(:restorable_memberships)

      measure_restore_time do
        throttle_batches(restorable.memberships.organization_memberships) do |membership|
          if organization = Organization.find_by_id(membership.subject_id)
            if membership.admin?
              organization.add_admin(user, adder: actor)
            else
              organization.add_member(user, action: membership.action, adder: actor)
            end
          end
        end

        throttle_batches(restorable.memberships.team_memberships) do |membership|
          if team = Team.find_by_id(membership.subject_id)
            team.add_member(user, adder: actor)

            if get_ability_permission(membership.action) == get_ability_permission(:admin)
              team.promote_maintainer(user)
            end
          end
        end

        throttle_batches(restorable.memberships.repository_memberships) do |membership|
          if repository = ::Repository.find_by_id(membership.subject_id)
            repository.add_member(user, action: membership.action)
          end
        end
      end

      restorable.restored(:restorable_memberships)
    end

    # Internal: Bulk insert sql.
    #
    # Returns a String.
    def self.insert_ignore_sql
      <<-SQL
        INSERT IGNORE INTO
          restorable_memberships
          (restorable_id,subject_type,subject_id,action)
        :values
      SQL
    end

    # Internal: Create an array with needed values from models.
    #
    # restorable_id - Integer id of Restorable.
    # memberships - Array of abilities.
    #
    # Returns an Array of arrays.
    def self.values(restorable_id, memberships)
      memberships.map do |membership|
        [
          restorable_id,
          membership.subject_type,
          membership.subject_id,
          Ability.actions[membership.action],
        ]
      end
    end

    # Internal: Convert read/write/admin symbols/strings to team permission strings like
    # pull/push/admin.
    #
    # Returns a String.
    def self.get_ability_permission(ability_action)
      Team::ABILITIES_TO_PERMISSIONS[ability_action]
    end

    # Internal: The metric name for statsd.
    #
    # Returns a Symbol.
    def self.metric_name
      :membership
    end
  end
end
