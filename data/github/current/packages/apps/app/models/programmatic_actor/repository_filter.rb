# typed: true
# frozen_string_literal: true

module ProgrammaticActor
  class RepositoryFilter
    class << self
      # Public: Determine if the filter will actually filter repositories.
      #
      # Returns a Boolean.
      def applicable?(actor)
        return false unless actor.instance_of?(User)
        actor.using_auth_via_integration? || actor.using_auth_via_user_programmatic_access?
      end

      # Public: Filter the list of repositories if the actor is using a form of
      # authentication that requires us to filter by programmatic permissions.
      #
      # NOTE: If the auth type is not one the method recognizes it will just
      # return all of the repository_ids as given.
      #
      # If you want to check that the filtering is being applied use
      # .applicable?
      #
      # actor:            User.
      # target:           Organization or User. The target of the programmatic actor.
      # repository_ids:   Array. The list of repo IDs on which to filter.
      # resource:         Symbol. Represents the type of fine-grained
      #                   permission that the actor must have on a repository in order for that
      #                   repository to be  returned in the filtered list.
      # augmentation:     Callable. Arbitrary code that can be supplied in
      #                   order to modify the list of filtered repositories after filtering has
      #                   been applied.
      # owner_ids:        Array. The list of owner IDs of the repositories being filtered.
      #
      # Returns an Array.
      def perform(actor:, target: nil, repository_ids: [], resource: nil, augmentation: nil, owner_ids: nil)
        GitHub.tracer.in_span("programmatic_actor.repository_filter.perform", kind: :internal) do |span|
          return repository_ids if repository_ids.empty?

          span.add_attributes("gh.programmatic_actor_filter.auth_type" => auth_type(actor), "gh.programmatic_actor_filter.repositories.count" => repository_ids.count)
          span.add_attributes("gh.programmatic_actor_filter.resource" => resource) if resource

          options = { repository_ids: repository_ids }

          accessible_repo_ids = if actor.using_auth_via_integration?
            # Not all u2s tokens have an installation bound to them. We should try to find one through the target
            # to scope down the search space.
            options[:current_integration_installation] = if actor.oauth_access.installation.present?
              actor.oauth_access.installation
            elsif target.present?
              IntegrationInstallation.find_by(integration_id: actor.oauth_access.application_id, target: target)
            end

            options[:permissions] = [resource] if resource
            options[:owner_ids] = owner_ids if owner_ids.present?

            actor.oauth_access.application.accessible_repository_ids(**options)
          elsif actor.using_auth_via_user_programmatic_access?
            options[:resource] = resource if resource
            options[:target] = target
            actor.programmatic_access.accessible_repository_ids(**options)
          else
            # should we support bots here?
            repository_ids
          end

          return accessible_repo_ids unless augmentation.respond_to?(:call)

          Array(augmentation.call(
            actor: actor,
            repository_ids: repository_ids,
            resource: resource,
            accessible_repository_ids: accessible_repo_ids
          )).uniq
        end
      end

      def perform_with_owner_and_repo_ids(actor:, target: nil, owner_and_repo_ids: {}, resource: nil, augmentation: nil)
        GitHub.tracer.in_span("programmatic_actor.repository_filter.perform_with_owner_and_repo_ids", kind: :internal) do |_span|
          return [] if owner_and_repo_ids.empty?

          repository_ids = owner_and_repo_ids.values.flatten.uniq

          options = {}

          accessible_repo_ids = if actor.using_auth_via_integration?
            # Not all u2s tokens have an installation bound to them. We should try to find one through the target
            # to scope down the search space.
            options[:current_integration_installation] = if actor.oauth_access.installation.present?
              actor.oauth_access.installation
            elsif target.present?
              IntegrationInstallation.find_by(integration_id: actor.oauth_access.application_id, target: target)
            end

            options[:owner_and_repo_ids] = owner_and_repo_ids
            options[:permissions] = [resource] if resource

            actor.oauth_access.application.accessible_repository_ids_by_owner(**options)
          elsif actor.using_auth_via_user_programmatic_access?
            options[:repository_ids] = repository_ids
            options[:resource] = resource if resource
            options[:target] = target

            actor.programmatic_access.accessible_repository_ids(**options)
          else
            repository_ids
          end

          return accessible_repo_ids unless augmentation.respond_to?(:call)

          Array(augmentation.call(
            actor: actor,
            repository_ids: repository_ids,
            resource: resource,
            accessible_repository_ids: accessible_repo_ids
          )).uniq
        end
      end

      private

      def auth_type(actor)
        if actor.using_auth_via_integration?
          "user_to_server"
        elsif actor.using_auth_via_user_programmatic_access?
          "user_programmatic_access"
        else
          "unknown"
        end
      end
    end
  end
end
