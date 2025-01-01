# typed: true
# frozen_string_literal: true

# Public: Belongs to a Restorable and serves as the public interface for
# restorables.
#
# Usage:
#
#  > org = Organization.find_by_login("github")
#  > user = User.find_by_login("lizzhale")
#  > direct_memberships = org.user_direct_abilities_for_organization_teams_and_repositories(user)
#  > assigned_issues = Issue.assigned_to(user).all
#
#  > organization_user_restorable = Restorable::OrganizationUser.start(org, user)
#  > organization_user_restorable.save_memberships(direct_memberships)
#  > organization_user_restorable.save_memberships_complete
#
#  > organization_user_restorable = Restorable::OrganizationUser.continue(org, user)
#  > organization_user_restorable.save_issue_assignments(assigned_issues)
#
#  > organization_user_restorable = Restorable::OrganizationUser.restorable(org, user)
#  > organization_user_restorable.restore(actor: actor)
#
class Restorable
  class OrganizationUser < ApplicationRecord::Domain::Restorables
    include Instrumentation::Model

    belongs_to :restorable
    belongs_to :organization
    belongs_to :user

    validates_presence_of :restorable, :organization_id, :user_id
    validates_uniqueness_of :restorable, scope: [:organization_id, :user_id]

    TYPES = [
      :restorable_memberships,
      :restorable_repositories,
      :restorable_repository_stars,
      :restorable_watched_repositories,
      :restorable_issue_assignments,
      :restorable_custom_email_routings,
    ]

    # Public: Takes an organization and a user and creates a new
    # Restorable::OrganizationUser record.
    #
    # organization - the organization the user was removed from.
    # user         - the user whose settings will be made restorable.
    #
    # Returns an OrganizationUser record
    def self.start(organization, user)
      return NullOrganizationUser.new unless organization && user

      restorable_organization_user = new({
        organization: organization,
        user: user,
      })
      restorable_organization_user.create_restorable

      if restorable_organization_user.save
        GitHub.dogstats.increment("restorable", tags: ["type:organization_user", "action:start", "valid:true"])
        restorable_organization_user
      else
        GitHub.dogstats.increment("restorable", tags: ["type:organization_user", "action:start", "valid:false"])
        NullOrganizationUser.new
      end
    end

    # Public: Finds the most recent Restorable::OrganizationUser record
    # for the given organization and user. Only returns a record with a `saving`
    # state. Used primarily in background jobs to continue saving records before
    # they are removed.
    #
    # organization - the organization the user was removed from.
    # user         - the user whose settings will be made restorable.
    #
    # Returns an OrganizationUser record
    def self.continue(organization, user)
      return NullOrganizationUser.new unless organization && user

      restorable_organization_user = most_recent(organization, user).first

      if restorable_organization_user && restorable_organization_user.saving?
        restorable_organization_user
      else
        NullOrganizationUser.new
      end
    end

    # Public: Finds the most recent Restorable::OrganizationUser record
    # the given organization and user. Only returns a record with a `restorable`
    # state. Mostly used by the UI in controllers and view models and before
    # queueing a restore job.
    #
    # organization - the organization the user was removed from.
    # user         - the user whose settings will be made restorable.
    #
    # Returns an OrganizationUser record
    def self.restorable(organization, user)
      return NullOrganizationUser.new unless organization && user

      restorable_organization_user = most_recent(organization, user).first

      if restorable_organization_user && restorable_organization_user.restorable?
        restorable_organization_user
      else
        NullOrganizationUser.new
      end
    end

    # Public: Find restorable memberships for a set of organization users.
    #
    # organization - the organization the users were removed from.
    # user_ids     - user identifiers whose settings might be restorable.
    #
    # Returns a ActiveRecord::Relation of restorable memberships (with user identifier).
    def self.restorable_memberships(organization, user_ids)
      select("restorable_organization_users.user_id, restorable_memberships.*")
        .where({
          organization_id: organization.id,
          user_id: user_ids,
        })
        .joins("JOIN restorable_memberships ON restorable_memberships.restorable_id = restorable_organization_users.restorable_id")
        .order("restorable_organization_users.id")
    end

    # Internal: Primary scope for finding most recent restorable settings for an
    # organization and a user.
    #
    # organization - Instance of Organization.
    # user - Instance of User.
    scope :most_recent, -> (organization, user) {
      where({
        organization_id: organization.id,
        user_id: user.id,
      }).order("id DESC")
    }

    # Public: Takes a user's membership information for Organizations, Teams,
    # and/or Repositories and makes those memberships restorable.
    #
    # memberships - a list of abilities
    def save_memberships(memberships)
      if memberships.empty?
        GitHub.dogstats.increment "restorable", tags: ["type:organization_user", "action:save_memberships", "error:empty"]
        GitHub.logger.info("memberships empty",
          "code.namespace": "Restorable::OrganizationUser", # per https://git.io/vi897
          "code.function": "save_memberships",
          "gh.org.id": T.must(organization).id,
          "gh.thisuser": T.must(user).id,
          timestamp: Time.now.utc.iso8601)
      end

      Restorable::Membership.backup(
        restorable: restorable,
        memberships: memberships
      )
    end

    # Public: Takes issues assigned to a user and makes those issues restorable.
    #
    # issues - an array of issues.
    def save_issue_assignments(issues)
      Restorable::IssueAssignment.backup(restorable: restorable, issues: issues)
    end

    # Public: Takes repositories watched by a user and makes those
    # newsie subscriptions restorable.
    #
    # repositories - an array of repositories that are extended with an ignored
    # method that returns true or false.
    def save_watched_repositories(repositories)
      Restorable::WatchedRepository.backup(restorable: restorable, repositories: repositories)
    end

    # Public: Takes repositories that are starred by a user and makes those
    # stars restorable.
    #
    # repositories  - list of repositories.
    def save_repository_stars(repositories)
      Restorable::RepositoryStar.backup(restorable: restorable, repositories: repositories)
    end

    # Public: Takes a collection of stars and makes those stars restorable. To replace the .save_repository_stars
    # method once the :persist_user_with_restorable_stars feature flag is fully shipped.
    #
    # stars - enumeration of StarEntity instances.
    def save_repository_stars_from_stars(stars)
      Restorable::RepositoryStar.backup_from_stars(restorable: restorable, stars: stars)
    end

    # Public: Takes a user's forks and makes those forks restorable.
    #
    # repositories - list of repositories.
    def save_repositories(repositories)
      Restorable::Repository.backup(restorable: restorable, repositories: repositories)
    end

    # Public: Takes a user's forks and makes those forks restorable.
    #
    # repositories - list of repositories.
    def save_custom_email_routings(email)
      Restorable::CustomEmailRouting.backup(
        restorable: restorable,
        org_id_and_email_hash: { organization_id => email },
      )
    end

    # Public: Mark restorable_memberships as saved.
    def save_memberships_complete
      save_restorable_complete(:memberships)
    end

    # Public: Mark restorable_issue_assignments as saved.
    def save_issue_assignments_complete
      save_restorable_complete(:issue_assignments)
    end

    # Public: Mark restorable_watched_repositories as saved.
    def save_watched_repositories_complete
      save_restorable_complete(:watched_repositories)
    end

    # Public: Mark restorable_repository_stars as saved.
    def save_repository_stars_complete
      save_restorable_complete(:repository_stars)
    end

    # Public: Mark restorable_repositories as saved.
    def save_repositories_complete
      save_restorable_complete(:repositories)
    end

    # Public: Mark restorable_custom_email_routings as saved.
    def save_custom_email_routings_complete
      save_restorable_complete(:custom_email_routings)
    end

    # Public: Restores records in a specific order.
    def restore(actor:)
      return unless restorable?

      Restorable::Membership.restore(restorable: restorable, user: user, actor: actor)
      Restorable::Repository.restore(restorable: restorable, organization: organization)
      Restorable::IssueAssignment.restore(restorable: restorable, user: user)
      Restorable::WatchedRepository.restore(restorable: restorable, user: user)
      Restorable::RepositoryStar.restore(restorable: restorable, user: user)
      Restorable::CustomEmailRouting.restore(restorable: restorable, user: user)

      instrument :restore_member, actor: actor
    end

    # Public: Is this Restorable::OrganizationUser ready to be restored? All
    # type states must be in :saved state.
    #
    # Returns true or false.
    def restorable?
      T.must(restorable).saved?(TYPES)
    end

    # Public: Is this Restorable::OrganizationUser in the process of saving?
    #
    # Returns true or false.
    def saving?
      T.must(restorable).saving?(TYPES)
    end

    def job_status
      Organization::JobStatus.find(RestoreOrganizationUserJob.job_id(user))
    end

    def event_prefix
      :org
    end

    def event_payload
      memberships = T.must(restorable)
        .memberships
        .team_and_repo_memberships
        .includes(:subject)
        .all

      restored_memberships = memberships.order(:id).map(&:subject).unshift(organization)

      {
        restored_memberships: restored_memberships,
        restored_memberships_count: restored_memberships.count,
        restored_repos_count: T.must(restorable).repositories.count,
        restored_issue_assignments_count: T.must(restorable).issue_assignments.count,
        restored_repo_watches_count: T.must(restorable).watched_repositories.count,
        restored_repo_stars_count: T.must(restorable).repository_stars.count,
        restored_custom_email_routings_count: T.must(restorable).custom_email_routings.count,
        user: T.must(user).display_login,
        user_id: T.must(user).id,
      }.merge(event_context)
    end

    def event_context(prefix: event_prefix)
      T.must(organization).event_context(prefix: prefix)
    end

    private

    def save_restorable_complete(restorable_name)
      restorable_type = "restorable_#{restorable_name}".to_sym
      restorable_metric_name = "save_#{restorable_name}_complete"

      if T.must(restorable).saved(restorable_type)
        GitHub.dogstats.increment("restorable", tags: ["type:organization_user", "action:#{restorable_metric_name}", "result:success"])
      elsif T.must(restorable).saved?(restorable_type)
        GitHub.dogstats.increment("restorable", tags: ["type:organization_user", "action:#{restorable_metric_name}", "result:resave_attempt"])
      else
        GitHub.logger.info(errors.full_messages.join(", "), {
          "code.namespace": "Restorable::OrganizationUser",
          "code.function": "save_restorable_complete",
          "gh.org.id": T.must(organization).id,
          "gh.thisuser": T.must(user).id,
          timestamp: Time.now.utc.iso8601,
        })
        GitHub.dogstats.increment("restorable", tags: ["type:organization_user", "action:#{restorable_metric_name}", "result:failure"])
      end
    end

  end
end
