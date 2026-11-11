# typed: false
# frozen_string_literal: true

class Restorable
  # Preserves the following during an LDAP team sync:
  #  - private user forks
  #
  # restorable = Restorable::LdapTeamSyncUser.start(team, member)
  # restorable.save_user_forks
  # restorable.restore
  class LdapTeamSyncUser < ApplicationRecord::Domain::Restorables
    belongs_to :restorable
    belongs_to :team
    belongs_to :member, class_name: "User"

    validates_presence_of :member_id
    validates_presence_of :restorable
    validates_presence_of :team_id

    # Public: Returns a new and persisted Restorable::LdapTeamSyncUser
    def self.start(team, member)
      record = new(team: team, member: member)
      record.create_restorable
      record.save!
      record
    end

    # Public: Find the restorables for a given team
    #
    # Returns an array of Restorable::LdapTeamSyncUser objects
    def self.team_restorables(team)
      scope = where(team_id: team.id)
      scope = scope.includes(:restorable)
      scope = scope.order("id DESC")

      scope
    end

    # Public: Save a user's private repo forks. This should be called before the
    # repositories are archived.
    #
    # Returns nothing
    def save_user_forks
      return unless persisted?

      forks = ::Repository.private_forks_for(organization: team.organization, belonging_to_user: member)
      Restorable::Repository.backup(restorable: restorable, repositories: forks)
    end

    # Public: Restores a team member's private forks if the member has access to
    # the parent repo and doesn't have an another fork in the same network.
    #
    # Returns nothing
    def restore
      return unless persisted?

      fork_ids = restorable.repositories.pluck(:archived_repository_id)
      fork_ids.each do |fork_id|
        next unless archived_fork = Repositories::Public.find_deleted(fork_id)
        next unless parent = ::Repositories::Public.find_active(archived_fork.parent_id)

        if parent.pullable_by?(member) && parent.find_fork_in_network_for_user(member).nil?
          ::Repository.restore(fork_id)
        end
      end
      restorable.restored(:restorable_repositories)
    end
  end
end
