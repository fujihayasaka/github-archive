# typed: false
# frozen_string_literal: true
require_relative "queries/actor_ids"
require_relative "queries/actor_ids_with_granular_permissions_on"
require_relative "queries/async_most_capable_action_between"
require_relative "queries/direct_ability_between"
require_relative "queries/direct_abilities_on_subject"
require_relative "queries/most_capable_ability_between"
require_relative "queries/most_capable_collaborator_abilities_from_actor"
require_relative "queries/most_capable_abilities_between_multiple_actors_and_subjects"
require_relative "queries/subject_ids"
require_relative "commands/clear_abilities_for_multiple_participants"

module Authorization
  class Service
    include Scientist

    # TODO: investigate if it makes sense to replace this method usages' in favor of
    # usages of `actor_ids_for_multiple_subjects`. Or drop actor_ids_for_multiple_subjects.
    #
    # actor_ids returns an array containing the ids of actors of a specific actor
    # type that have access to a specific subject. By default only direct
    # abilities are checked.
    #
    # Optionally you can specify:
    #  * actor_ids: a subset of the actors among which select the ids.
    #  * action: a symbol in [:read, :write, :admin] indicating the level of permissions.
    #  * through: an array of classes of connectors through which an actor
    #      gains indirect abilities. ex [Team]
    #
    # Examples:
    #   Give me all the ids of teams that have access to this repository
    #   => actor_ids(actor_type: Team, subject: repository)
    #   Give me all the ids of teams that have access to this repository,
    #   among a a set of candidates
    #   => actor_ids(actor_type: Team, actor_ids: candidates, subject: repository)
    #   Give me all the ids of users that are administrators of a Team
    #   => actor_ids(actor_type: User, subject: team, action: admin)
    #
    # Returns [Integer]
    def actor_ids(actor_type:, subject:, actor_ids: :any, action: :any, through: [])
      record_stats "actor_ids" do
        Authorization::Queries::ActorIds.new(actor_type: actor_type, subject: subject, actor_ids: actor_ids, action: action, through: through).execute.flatten
      end
    end

    # Find all the actors of a specific actor_type that has the specified permissions
    # on subject.
    #
    #   actor_type:    String or Class of the type of actor (e.g. IntegrationInstallation)
    #   subject_type:  The class of the type of Subject, (one of User, Organization, or Repository).
    #   subject_ids:   The subject ids of permissions (e.g. A repo id an Integration is installed on)
    #   owner_ids:     The owner of the subject if you want to look for indirect permissions.
    #   permissions:   Array of permissions (e.g. [:pull_requests, :metadata])
    #   min_action:    A Symbol in [:read, write, :admin] indiciating the minimum level of permission (defaults to :read).
    #
    # Examples:
    #   Give me all the ids of IntegrationInstallations that have pull_request: :read or greater on a repo
    #   => actor_ids_with_granular_permissions_on(actor_type: 'IntegrationInstallation', subject_type: Repository, subject_ids: repo.id, permissions: [:pull_requests])
    #
    #   Give me all the ids of IntegrationInstallations that have pull_request: :write or greater on a repo
    #   => actor_ids_with_granular_permissions_on(actor_type: 'IntegrationInstallation', subject_type: Repository, subject_ids: repo.id, permissions: [:pull_requests], min_action: :write)
    #
    # Returns [Integer]
    def actor_ids_with_granular_permissions_on(actor_type:, subject_type:, subject_ids:, owner_ids: nil, permissions:, min_action: :read)
      record_stats "actor_ids_with_granular_permissions_on" do
        Authorization::Queries::ActorIdsWithGranularPermissionsOn.new(
          actor_type: actor_type,
          subject_type: subject_type,
          subject_ids: subject_ids,
          owner_ids: owner_ids,
          permissions: permissions,
          min_action: min_action,
        ).execute
      end
    end

    # direct_ability_between returns the fist direct ability found between an
    # actor and a subject
    #
    # actor - Actor (user, org, team)
    # subject - Subject (org, repo)
    # action (Optional) - if provided, it will only return an ability with the
    #   exact provided action if exists.
    #
    # Returns the Ability or nil.
    def direct_ability_between(actor:, subject:, action: :any)
      Authorization::Queries::DirectAbilityBetween.new(actor: actor, subject: subject, action: action).execute
    end

    # direct_abilities_on_subject returns an array returns all the direct
    # abilities to a particular subject.
    #
    # subject - Subject (org, repo)
    # actor_type (Optional) - if provided, it will only return abilities from
    #   the subject to actors of the given type
    # action (Optional) - if provided, it will only return abilities with the
    #   exact provided action.
    #
    # TODO: add actor_ids to restrict result set, and be symmetric to direct_abilities_for_actor
    # TODO: add a means of fragment caching to, once may abilities are fetched, if then an individual
    # ability is checked, it doesn't go to the DB again.
    #
    # Returns [Ability]
    def direct_abilities_on_subject(subject:, actor_type: :any, action: :any)
      record_stats "direct_abilities_on_subject" do
        Authorization::Queries::DirectAbilitiesOnSubject.new(subject: subject, actor_type: actor_type, action: action).execute
      end
    end

    # most_capable_ability_between returns the most capable direct or indirect
    # Ability the given actor has on the given subject
    #
    # actor - Actor (user, org, team)
    # subject - Subject (org, repo)
    #
    # Returns the Ability or nil.
    def most_capable_ability_between(actor:, subject:)
      Authorization::Queries::MostCapableAbilityBetween.new(actor: actor, subject: subject).execute
    end

    # most_capable_action_between returns the most capable direct or indirect
    # action the given actor has on the given subject
    #
    # actor - Actor (user, org, team)
    # subject - Subject (org, repo)
    #
    # Returns the action or nil.
    def most_capable_action_between(actor:, subject:)
      async_most_capable_action_between(actor: actor, subject: subject).sync
    end

    # async_most_capable_action_between returns a Promise for the most capable direct or indirect
    # action the given actor has on the given subject
    #
    # actor - Actor (user, org, team)
    # subject - Subject (org, repo)
    #
    # Returns Promise<symbol> or Promise<nil>.
    def async_most_capable_action_between(actor:, subject:)
      # skip the cache for now, while we test the correctness of the query itself
      Authorization::Queries::AsyncMostCapableActionBetween.new(actor: actor, subject: subject).async_execute
    end

    # most_capable_collaborator_abilities_from_actor returns an array containing the most capable
    # collabortor abilities between the actor and a set of subjects identified by the subject
    # type and subject_ids.
    # WARNING: It does NOT include implicit abilities between org admins and
    # subjects owned by organization. Reach out to #authorization if you need assistance
    # in how to get that information.
    #
    # actor - Actor (user, team)
    # subject_type - The type of the subject
    # subject_ids - The set of ids of the given subject type, which most capable abilities
    # are going to be returned
    #
    # Returns [Ability]
    def most_capable_collaborator_abilities_from_actor(actor:, subject_type:, subject_ids:, min_action: :read)
      record_stats "most_capable_collaborator_abilities_from_actor" do
        Authorization::Queries::MostCapableCollaboratorAbilitiesFromActor.new(actor: actor, subject_type: subject_type, subject_ids: subject_ids, min_action: min_action).execute
      end
    end

    # most_capable_abilities_between_multiple_actors_and_subjects returns an array containing the most capable
    # abilities between a set of actors and a set of subjects identified by the subject
    # type and subject objects themselves. It's a way of batching `most_capable_ability_between`
    # for a set of actors and and a set of subjects.
    #
    # subject should implement owning_organization_id in order to derive/fulfil original API expectation
    # of returning "admin-on-owner" abilities. See more in https://github.com/github/github/pull/139312
    #
    # actor_ids - The set of ids of the given actor type
    # actor_type - The type of the actor
    # subject_type - The type of the subject
    # subject - The set of subjects to check for. Should implement "owning_organization_id"
    #
    # Returns [Ability]
    def most_capable_abilities_between_multiple_actors_and_subjects(actor_ids:, actor_type:, subjects:, subject_type:)
      record_stats "most_capable_abilities_between_multiple_actors_and_subjects" do
        Authorization::Queries::MostCapableAbilitiesBetweenMultipleActorsAndSubjects.new(
          actor_ids: actor_ids,
          actor_type: actor_type,
          subjects: subjects,
          subject_type: subject_type,
        ).execute
      end
    end

    # TODO: make subject_ids and actor_ids related operations symmetric.
    #
    # subject_ids returns an array containing the ids of the subject type for
    # which a specific actor has direct access to.
    #
    #  * through: an array of classes of connectors through which an actor
    #      gains indirect abilities. ex [Team]
    #  * actions (optional): If provided, will only return subjects that the
    #      actor has the specified permissions on the subjects.
    #      ex [:write, :admin]
    #
    # Examples:
    #  Give me all the ids of teams for which an organization has access to
    #  => subject_ids(actor: organization, subject_type: Team)
    #
    #  Give me all the ids of repos for which a user has access to
    #  => subject_ids(actor: user, subject_type: Repository)
    #
    # Returns [Integer]
    def subject_ids(actor:, subject_type:, through: [], actions: :any, subject_ids: :all)
      record_stats "subject_ids" do
        Authorization::Queries::SubjectIds.new(actor: actor, subject_type: subject_type, through: through, actions: actions, subject_ids: subject_ids).execute
      end
    end

    # clear_abilities_for_multiple_participants deletes the abilities where any of the given
    # participant_type and participant_ids is a participant (either an actor or a subject).
    #
    # It also deletes it's dependants. (Any ability whose parent is one being deleted)
    #
    # participant_type - The type of the participant, which abilities we want to delete
    # participant_ids - The set of ids of the given participant type, which abilitie we want to delete
    #
    # Return nothing
    def clear_abilities_for_multiple_participants(participant_type:, participant_ids:)
      Authorization::Commands::ClearAbilitiesForMultipleParticipants.new(participant_type: participant_type, participant_ids: participant_ids).execute
    end

    private

    def record_stats(method_name)
      begin
        tags = ["method: #{method_name}"]
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        yield
      ensure
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        GitHub.dogstats.distribution("authorization.service.dist", (end_time - start_time) * 1_000, tags: tags)
      end
    end
  end
end
