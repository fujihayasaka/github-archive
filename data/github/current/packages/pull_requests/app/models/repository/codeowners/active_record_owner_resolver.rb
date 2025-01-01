# typed: true
# frozen_string_literal: true

require "codeowners"

class Repository
  class Codeowners
    class ActiveRecordOwnerResolver < ::Codeowners::OwnerResolver
      extend T::Sig

      LockedError = Class.new(StandardError)

      sig { params(repository: Repository).void }
      def initialize(repository)
        super()
        @repository = repository
        @locked = false
      end

      sig { params(args: T::Array[::Codeowners::Owner]).void }
      def register_owners(*args)
        if @locked
          # The goal of this class is to minimise database queries, which means
          # the first call to #resolve will load and memoize _all_ users,
          # so it doesn't make sense to register more owners after we've hit
          # the database.
          raise LockedError, "Cannot register more owners after resolving"
        else
          super
        end
      end

      sig { params(owner_identifier: String).returns(T.any(User, Team, NilClass)) }
      def resolve(owner_identifier)
        owner = super

        return nil if owner.nil?

        @locked = true

        found_owner = if owner.username?
          users_by_username[owner_identifier.downcase]
        elsif owner.email?
          users_by_email[owner_identifier.downcase]
        elsif owner.teamname?
          teams_by_teamname[owner_identifier.downcase]
        end
        found_owner if owners_with_write_access.include?(found_owner)
      end

      sig { params(owner_identifiers: T::Array[String]).returns(T::Array[T.any(User, Team)]) }
      def resolve_many(owner_identifiers)
        owner_objects = @owners.values_at(*owner_identifiers.map(&:downcase)).compact
        return [] if owner_objects.empty?

        @locked = true

        owners_to_find_by_username = []
        owners_to_find_by_email = []
        owners_to_find_by_teamname = []

        owner_objects.each do |oo|
          owners_to_find_by_username << oo.identifier.downcase if oo.username?
          owners_to_find_by_email << oo.identifier.downcase if oo.email?
          owners_to_find_by_teamname << oo.identifier.downcase if oo.teamname?
        end

        found_owners =  (users_by_username.values_at(*owners_to_find_by_username) +
                        users_by_email.values_at(*owners_to_find_by_email) +
                        teams_by_teamname.values_at(*owners_to_find_by_teamname)).compact

        found_owners & owners_with_write_access
      end

      sig { params(owner: ::Codeowners::Owner).returns(String) }
      def suggestion_for_unresolved_owner(owner)
        actor = if owner.email?
          "a user with the email address #{owner.identifier}"
        elsif owner.teamname?
          "the team #{owner.identifier}"
        else
          owner.identifier
        end

        requirements = ["exists"]
        requirements << "is publicly visible" if owner.teamname?
        requirements << "has write access to the repository"

        "make sure #{actor} #{requirements.to_sentence}"
      end

      sig { returns(T::Hash[String, User]) }
      def users_by_username

        return @users_by_username if defined?(@users_by_username)

        users = User.where(login: logins)

        @users_by_username = users.index_by { |user| "@#{user.display_login.downcase}" }
      end

      private

      sig { returns(T::Hash[String, ::Codeowners::Owner]) }
      attr_reader :owners
      sig { returns(Repository) }
      attr_reader :repository

      sig { returns(T::Array[String]) }
      def logins
        owners.values.select(&:username?)
          .map { |owner| owner.identifier[1..-1] }
      end

      sig { returns(T::Hash[String, User]) }
      def users_by_email
        return @users_by_email if defined?(@users_by_email)

        @users_by_email = User.find_by_emails(emails, verified: GitHub.email_verification_enabled?)
      end

      sig { returns(T::Array[String]) }
      def emails
        owners.values.select(&:email?).map(&:identifier)
      end

      sig { returns(T::Hash[String, Team]) }
      def teams_by_teamname
        return @teams_by_teamname if defined?(@teams_by_teamname)
        teams = find_teams
        GitHub::PrefillAssociations.prefill_associations(teams, :organization)

        @teams_by_teamname = teams.each_with_object({}) do |team, by_teamname|
          teamname = "@#{team.combined_slug.downcase}"
          by_teamname[teamname] = team
        end
      end

      sig { returns(ActiveRecord::Relation) }
      def find_teams
        slugs = team_slugs
        return Team.none unless repository.owner&.organization?
        return Team.none unless slugs.any?

        T.must(repository.owner).teams.closed.where(slug: slugs).order(:slug)
      end

      sig { returns(T::Array[String]) }
      def team_slugs
        return [] unless T.must(repository.owner).organization?

        owners.values.select(&:teamname?).each_with_object([]) do |owner, org_teams|
          combined_slug = owner.identifier[1..-1]
          org, slug = combined_slug.split("/", 2)

          org_teams << slug if org.casecmp?(T.must(repository.owner).display_login)
        end
      end

      sig { returns(T::Array[T.any(User, Team)]) }
      def owners_with_write_access
        return @owners_with_write_access if defined?(@owners_with_write_access)

        @owners_with_write_access = users_with_write_access + teams_with_write_access
      end

      sig { returns(T::Array[User]) }
      def users_with_write_access
        users = users_by_username.values + users_by_email.values
        allowed_user_ids = repository.user_ids_with_privileged_access(min_action: :write, actor_ids_filter: users.map(&:id))

        users.select do |user|
          allowed_user_ids.include?(user.id)
        end
      end

      sig { returns(T::Array[Team]) }
      def teams_with_write_access
        teams = teams_by_teamname.values
        allowed_team_ids = team_ids_with_direct_or_indirect_write_access(teams)

        teams.select do |team|
          allowed_team_ids.include?(team.id)
        end
      end

      # Private: Given a list of teams, returns an Array of IDs for the teams
      # which have write access. Either directly or indirectly from a parent team.
      #
      # teams     - An Array of Teams.
      #
      # Returns an Array of Team IDs.
      sig { params(teams: T::Array[Team]).returns(T::Array[Integer]) }
      def team_ids_with_direct_or_indirect_write_access(teams)
        return [] unless repository.in_organization?
        return [] if teams.empty?

        ancestor_map = teams.each_with_object({}) do |team, map|
          map[team.id] = team.ancestor_ids
        end

        ids_with_write_access = if repository.owner&.feature_enabled?(:codeowners_check_all_repo_role)
          repository.team_ids_with_direct_privileged_access(
            min_action: :write,
            actor_ids_filter: ancestor_map.flatten(2),
          )
        else
          repository.actor_ids(
            type: Team,
            min_action: :write,
            actor_ids_filter: ancestor_map.flatten(2)
          )
        end

        ancestor_map.each_with_object([]) do |(team_id, ancestor_ids), has_access|
          direct_access = ids_with_write_access.include?(team_id)
          indirect_access = (ancestor_ids & ids_with_write_access).any?

          has_access << team_id if direct_access || indirect_access
        end
      end
    end
  end
end
