# typed: true
# frozen_string_literal: true

# Internal: This is the parent class for all requests where a User and a
# granular actor both need to be authorized.
#
# Examples include:
#
# - GitHub App user to server requests
# - UserProgrammaticAccess requests (PATS v2)
#
# This class should not be used directly, but instead should be inherited from.
module Platform
  module Authorization
    class UserViaGranularActorAuthorizer < AuthorizerBase
      ########################
      # Methods to override. #
      ########################

      def forbidden_message
        "Resource not accessible by this actor"
      end

      def github_app_user_to_server_request?; false; end

      def granular_actor_on_business_target(target);     nil; end
      def granular_actor_on_organization_target(target); nil; end
      def granular_actor_on_repository(repository);      nil; end
      def granular_actor_on_user_target(target);         nil; end

      def granular_actor_on_business_target?(target);     false; end
      def granular_actor_on_organization_target?(target); false; end
      def granular_actor_on_repository?(repository);      false; end
      def granular_actor_on_user_target?(target);         false; end

      def hydrated_bot_for(actor); nil; end
      def hydrated_bot_with_null_granular_actor; nil; end

      def preloaded_granular_actor;            nil; end
      def preloaded_granular_actor_permitted?; false; end

      def preloaded_parent_granular_actor; nil; end
      def preloaded_parent_granular_actor_permitted?; false; end

      def resource_missing_error_message
        ":resource or :repo is required for this type of request"
      end

      ##########################################
      # Do not override methods defined below. #
      ##########################################

      # Public: This is the main method for determining if the current request
      # is authorized. We check the following:
      #
      # - If the `verb` has been opted-in to this type of request, currently
      # this is done by the :user_allowed_via_integration key.
      # - If the granular actor is authorized (see #granular_actor_access_allowed?)
      # - If the current_user is authorized.
      #
      # Returns a Boolean.
      def authorized?(verb, options)
        options = options.dup

        # From https://github.com/github/github/pull/84396
        # This flag is just to enforce whether an installation is needed to get
        # a particular resource.
        #
        # See https://github.com/github/github/pull/84396#issuecomment-370054554
        # for a full explanation.
        options[:approved_integration_required] = true if options[:approved_integration_required].nil?

        resource = options[:resource] || options[:repo]

        if resource.nil?
          if options.key?(:resource) || options.key?(:repo)
            return false
          else
            error = Platform::Errors::ResourceMissing.new(resource_missing_error_message)

            if Rails.env.production?
              Failbot.report(error)
              return false
            else
              raise Platform::Errors::ResourceMissing, resource_missing_error_message
            end
          end
        end

        if Platform::ResourceUtils.is_dashboard_type?(resource)
          # Dashboards will probably eventually be enabled for users.
          # If they are, then the endpoint needs to do filtering, but
          # we don't have to check whether the "resource" is readable by
          # the user and/or the integration.
          # By definition, the dashboard is readable by the user, and the
          # filtering will have to take the token into account.
          auth_context.set_forbidden_message(forbidden_message)
          return auth_context.user_via_granular_actor_request_allowed?
        end

        # If the forbid option is set, then we always want to return a 403 rather than a 404.
        if options[:forbid]
          auth_context.set_forbidden_message(forbidden_message)
        end

        # Skip readable_by_* check if one user is trying to interact with
        # another user. These readable_by_* will always return false, and
        # we're not leaking existence.
        unless user_to_user_interaction?(verb)
          # Bail out with a 404 so that we don't leak existence
          unless resource.readable_by?(auth_context.current_user)
            trace_step(:guard_clause, ":resource is not readable_by? current_user", { status: 404 })
            return false
          end

          # Bail out with a 404 so that we don't leak existence
          unless can_see_resource?(resource)
            trace_step(:guard_clause, "existence of resource cannot be revealed to current_user", { status: 404 })
            return false
          end
        end

        if granular_actors_forbidden?(verb, options) || \
            !auth_context.access_grant(verb, options).access_allowed?
          auth_context.set_forbidden_message(forbidden_message)
          return false
        end

        true
      end

      # Internal: Has user-via-granular-actor access been explicitly forbidden,
      # or does the fine-grained actor's parent grant have insufficient access
      # to the given resource?
      #
      # Returns a Boolean.
      def granular_actors_forbidden?(verb, options)
        !auth_context.user_via_granular_actor_request_allowed? || !granular_actor_access_allowed?(verb, options)
      end

      # Get the parent resource against which AuthZ checks should be
      # run. In most cases this will be repository in which the resource lives.
      #
      # Returns a resource.
      def authz_resource_parent(resource)
        case resource
        when PublicKey
          resource.owner
        when Platform::InternalResource
          resource.resource
        when Codespace
          # Codespaces have a backing repository, but we want to look at the
          # codespace itself for authz, not the backing repository.
          resource
        else
          resource.try(:repository) || resource
        end
      end

      # Internal: This logic dictates whether the granular parent (Integration,
      # UserProgrammaticAccess, etc) is authorized on the `verb` action. To do
      # this we look at the following:
      #
      # - Can the parent "see" the resource, for GitHub Apps this is having an
      # installation on the target
      # - Is the granular actor (IntegrationInstallation,
      # *ProgrammaticAccessGrant, etc) able to perform the action (`verb`) as a
      # Bot with the actor hydrated (server-to-server request).
      #
      # If both of these are true (with some expections) then the parent is
      # authorized.
      #
      # Returns a Boolean.
      def granular_actor_access_allowed?(verb, options)
        if github_app_user_to_server_request?
          return true unless options.fetch(:installation_required, true)
        end

        granular_actor = if (auth_context.current_repo_loaded? || auth_context.repo_nwo_from_path.present?) && !template_repo_creation_interaction?(verb)
          return true if !options[:approved_integration_required] && auth_context.current_repo.public?

          # If the current repo is a public template, an explicit access is not required to access it
          # and there are write endpoints like cloning we allow in the initial control access.
          #
          # See https://github.com/github/github/pull/185309.
          if auth_context.current_repo.template? && auth_context.current_repo.public? && (verb == :get_repo)
            return true
          end

          case verb
          when :create_fork
            # When creating forks, attempt to fetch a grant on the target
            target = options[:organization] ? options[:organization] : auth_context.current_user
            granular_actor_for(target)
          else
            granular_actor_for(auth_context.current_repo)
          end
        else
          resource = options[:resource]

          # Special case resources that are not bound to to a granular actor, but
          # are needed for AuthZ to be successful.
          case resource
          when PublicResource, Platform::GraphqlUserResource, Gist, GistComment
            return true
          when IntegrationInstallation
            # In non-repo user-to-server requests, if the resource is an
            # installation (not scoped) then we allow granular actor checks to
            # be skipped if the current App owns the installation.
            if github_app_user_to_server_request? && resource.integration_id == auth_context.current_integration.id
              return true
            end
          when Integration
            if auth_context.user_programmatic_access_request?
              return auth_context.access_grant(verb, options).access_allowed?
            end
          end

          # In the event that an Organization _and_ User are in play,
          # rely on the Organization having a grant :|
          #
          # See https://github.com/github/ecosystem-apps/issues/560
          if resource.is_a?(User) && options[:organization].is_a?(Organization)
            resource = options[:organization]
          end

          if user_resource?(verb)
            # In the case when the resource is a user resource like public keys
            # or gpg keys, we want the grant on the current user and not on the
            # resource.
            granular_actor_for(auth_context.current_user)
          else
            granular_actor_for(resource)
          end
        end

        # In the event we've preloaded an granular actor during the AuthZ
        # process, go ahead and set it here.
        #
        # We don't set it at the top because there are special return cases,
        # that take precedent.
        if preloaded_granular_actor_permitted? && preloaded_granular_actor
          granular_actor = preloaded_granular_actor
        end

        if (bot = fetch_bot_user(granular_actor, verb))
          bot_options = options.dup
          bot_options[:user] = bot

          send_along_current_user_as_authenticated_user = !github_app_user_to_server_request? || \
            (github_app_user_to_server_request? && auth_context.current_user.using_auth_via_integration?)

          if send_along_current_user_as_authenticated_user
            bot_options[:authenticated_user] = auth_context.current_user
          end

          return auth_context.access_grant(verb, bot_options).access_allowed?
        end

        false
      end

      # Internal: Determines if the parent can "see" the provided resource
      # through one of it's children through permissions. For a GitHub
      # Apps this would be an IntegrationInstallation.
      #
      # Returns a Boolean.
      def can_see_resource?(resource)
        resource = authz_resource_parent(resource)

        # Special edgecases that don't fit the normal AuthZ patterns.
        case resource
        when DiscussionPost, DiscussionPostReply
          return can_see_resource?(auth_context.current_resource_owner)
        when Gist, GistComment
          return true
        when GitSigningSshPublicKey, GpgKey, Platform::PublicResource, Platform::GraphqlUserResource, PublicKey, SecurityAdvisory, AdvisoryDB::GlobalAdvisoriesResource
          # For EMUs, CAP policies will be enforced so permissions don't matter so much
          # for these "Public" resources (nothing in EMUs is public)
          return true
        when Integration
          return true if resource.public_visibility?
          # Currently PATv2 actors cannot see private integrations
          return false unless github_app_user_to_server_request?

          return resource == auth_context.current_integration
        when IntegrationInstallation
          return resource.integration == auth_context.current_integration
        when Project, Team, Codespace, MemexProject
          return can_see_resource?(resource.owner)
        when SubIssue
          return can_see_resource?(resource.source&.repository)
        when Repository
          return true if resource.public?
        when User
          return resource == auth_context.current_user if resource.user? && !auth_context.graphql_request?
        end

        granular_actor_found = case resource
        when Business
          granular_actor_on_business_target?(resource)
        when Platform::InternalResource
          granular_actor_on_organization_target?(resource.resource)
        when Organization
          granular_actor_on_organization_target?(resource)
        when Repository
          # Yikes! This is gnarly but this prevents us pushing GraphQL "async"
          # concerns down into the Repository package, where no GraphQL stuff
          # can be found today.
          resource.async_owner.then do |owner|
            GitHub::PrefillAssociations.prefill_associations(
              [resource],
              [:owner],
              available_records: [owner]
            )
            granular_actor_on_repository?(resource)
          end.sync
        when User
          granular_actor_on_user_target?(resource)
        else
          false
        end

        unless granular_actor_found
          trace_step(:can_see_resource, "no granular actor found for resource of type '#{resource.class}'")
          return false
        end

        unless preloaded_granular_actor_permitted? && preloaded_granular_actor.present?
          return granular_actor_found
        end

        unless preloaded_parent_granular_actor_permitted? && preloaded_parent_granular_actor.present?
          return granular_actor_found
        end

        # For GitHub Apps user-to-server requests.
        # To try and maintain the consistency of 404's vs 403's
        # we want to compare the installation found vs the installation
        # we have loaded.
        #
        # We use the parent installation because the only
        # installations that will be loaded at this point
        # are ScopedIntegrationInstallations.
        granular_actor_for(resource) == preloaded_parent_granular_actor
      end

      def explicit_access_required?(verb)
        if auth_context.graphql_request?
          return false if auth_context.request_authn_context.read_request?
          # We do not need explicit access when checking for basic visibility
          return false if verb == :v4_get_repo
        else
          return false unless auth_context.write_request?
        end

        !user_to_self_interaction?(verb)
      end

      def fetch_bot_user(granular_actor, verb)
        return hydrated_bot_for(granular_actor) if granular_actor
        return unless granular_actor.nil? && !explicit_access_required?(verb)

        hydrated_bot_with_null_granular_actor
      end

      # Internal: Find the granular actor that has access to the resource either
      # explicitly or through the owner of the given resource.
      #
      # Example:
      #
      #   >> resource = nwo("github/github")
      #   >> granular_actor_for(resource)
      #   => #<IntegrationInstallation, target_id: 9919, target_type: "User" ...>
      #
      # Returns an ActiveRecord object or nil.
      def granular_actor_for(resource)
        resource = authz_resource_parent(resource)

        case resource
        when Business
          granular_actor_on_business_target(resource)
        when Codespace, Project, Team, MemexProject
          granular_actor_for(resource.owner)
        when DiscussionPost, DiscussionPostReply
          granular_actor_for(auth_context.current_resource_owner)
        when Organization
          granular_actor_on_organization_target(resource)
        when Repository
          granular_actor_on_repository(resource)
        when User
          granular_actor_on_user_target(resource)
        else
          nil
        end
      end

      USER_TO_SELF_INTERACTIONS = %i(
        add_user_emails
        add_public_key
        delete_user_emails
        remove_public_key
        toggle_email_visibility
      )

      USER_TO_USER_INTERACTIONS = %i(
        follow
        get_public_member
        list_installation_repositories_for_user
        list_public_members
        read_requested_bot_user
        read_user_following
        unfollow
        v4_get_user_org_memberships
      )

      USER_RESOURCES = %i(
        add_public_key
        follow
        remove_gpg_key
        remove_public_key
        remove_ssh_signing_key
        unfollow
      )

      TEMPLATE_REPO_CREATION_INTERACTIONS = %i(
        create_repo_for_org_from_template
        create_private_repo_for_org_from_template
        create_repo_from_template
        create_private_repo_from_template
      )

      def user_resource?(verb)
        USER_RESOURCES.include?(verb)
      end

      def user_to_self_interaction?(verb)
        USER_TO_SELF_INTERACTIONS.include?(verb)
      end

      def user_to_user_interaction?(verb)
        USER_TO_USER_INTERACTIONS.include?(verb)
      end

      def template_repo_creation_interaction?(verb)
        TEMPLATE_REPO_CREATION_INTERACTIONS.include?(verb)
      end
    end
  end
end
