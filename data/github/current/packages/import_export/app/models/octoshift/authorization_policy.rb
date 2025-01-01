# typed: true
# frozen_string_literal: true

module Octoshift
  class AuthorizationPolicy
    DEFAULT_AUTHORIZER = Permissions::Enforcer
    DEFAULT_ROLE_GRANTER = Permissions::Granters::RoleGranter
    IMPORT_ACTION = :run_org_migration
    EXPORT_ACTION = :run_org_migration

    class ActorNotFoundError < StandardError; end

    class RoleGranterError < StandardError; end

    class InvalidActorTypeError < StandardError; end

    class UserDoesNotBelongToOrgError < StandardError; end

    def self.can_import_repo?(user:, owner:, authorizer: DEFAULT_AUTHORIZER)
      authorized?(user, owner, IMPORT_ACTION, authorizer)
    end

    def self.can_export_repo?(user:, owner:, authorizer: DEFAULT_AUTHORIZER)
      authorized?(user, owner, EXPORT_ACTION, authorizer)
    end

    # Public: Checks if an actor has the migrator role.
    #
    # actor  - The actor to check for the migrator role.
    # target - The target the actor is checked against.
    #
    # Returns a Boolean indicating whether the role was granted or not.
    def self.has_octoshift_migrator_role?(actor, target)
      Role.octoshift_migrator_role.user_roles.where(
        actor_type: actor.type,
        actor_id: actor.id,
        target_type: target.type,
        target_id: target.id
      ).exists?
    end

    # Public: Grants the migrator role to a user or a team
    #
    # actor_type [String] - Specifies the type of the actor, can be either USER or TEAM
    # actor [String] - The user login or Team slug to grant the migrator role
    # organization [Organization] - The organization that the user/team belongs to
    # role_granter [Object] - The role granter class. It is set to Permissions::Granters::RoleGranter by default
    #
    # Returns a Permissions::Granters::RoleGrantResult
    # Raises a GrantFailure if granting was not successful
    # Raises an ActorNotFoundError if the actor wasn't found
    # Raises an InvalidActorTypeError if the actor type is anything other than USER or TEAM
    # Raises a UserDoesNotBelongToOrgError if the actor is a USER and not a member of the organization
    def self.grant_octoshift_migrator!(actor_type:, actor:, organization:, role_granter: DEFAULT_ROLE_GRANTER)
      loaded_actor = load_actor(actor_type, actor, organization)

      unless loaded_actor.is_a?(Team) || organization.member?(loaded_actor)
        raise UserDoesNotBelongToOrgError.new("#{loaded_actor.display_login} is not a member of #{organization.display_login} organization.")
      end

      role_granter.new(actor: loaded_actor, target: organization, role: Role.octoshift_migrator_role).grant_unless_exists!
    rescue ActiveRecord::RecordInvalid, Permissions::Granters::RoleGranter::GrantFailure => e
      raise RoleGranterError.new(e.message)
    end

    # Public: Revokes the migrator role from a user or a team
    #
    # actor_type [String] - Specifies the type of the actor, can be either USER or TEAM
    # actor [String] - The user login or Team slug to revoke the migrator role from
    # organization [Organization] - The organization that the user/team belongs to
    # role_granter [Object] - The role granter class. It is set to Permissions::Granters::RoleGranter by default
    #
    # Returns a Permissions::Granters::RoleGrantResult
    # Raises a GrantFailure if revoking was not successful
    # Raises an ActorNotFoundError if the actor wasn't found
    # Raises an InvalidActorTypeError if the actor type is anything other than USER or TEAM
    def self.revoke_octoshift_migrator!(actor_type:, actor:, organization:, role_granter: DEFAULT_ROLE_GRANTER)
      loaded_actor = load_actor(actor_type, actor, organization)
      role_granter.new(actor: loaded_actor, target: organization, role: Role.octoshift_migrator_role).revoke_if_exists!
    rescue ActiveRecord::RecordInvalid, Permissions::Granters::RoleGranter::GrantFailure => e
      raise RoleGranterError.new(e.message)
    end

    class << self
      private

      def authorized?(user, owner, action, authorizer)
        return false unless user
        return false unless owner
        authorizer.authorize(
          action: action,
          actor: user,
          subject: owner
        ).allow?
      end

      def load_actor(actor_type, actor, organization)
        case actor_type
        when "USER"
          User.find_by_login(actor) || (raise ActorNotFoundError.new("Could not find the user: '#{actor}'"))
        when "TEAM"
          Team.with_org_name_and_slug(organization.login, actor) || (raise ActorNotFoundError.new("Could not find the team: '#{actor}'"))
        else
          raise InvalidActorTypeError.new("Invalid actor type: '#{actor_type}'")
        end
      end
    end
  end
end
