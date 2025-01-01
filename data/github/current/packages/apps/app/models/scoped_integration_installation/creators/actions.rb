# typed: true
# frozen_string_literal: true

# This module is specifically for repository scoped access and
# is used exclusively via an internal REST API endpoint
# that is utilized by GitHub Actions.
class ScopedIntegrationInstallation
  module Creators
    class Actions < ScopedIntegrationInstallation::Creators::Base
      include GitHub::Memoizer
      include ScopedIntegrationInstallation::PermissionRowsGenerator

      CACHE_NAMESPACE = "generate_v2_scoped_token"
      MISSING_PULL_REQUEST_ACCESS = "This installation does not have Pull Request access, and therefore cannot grant other pull request based permissions."
      MISSING_ACTIONS_ACCESS = "This installation does not have Actions access, and therefore cannot grant other Actions based permissions."
      MAXIMUM_EXPIRATION_EXTENSION_THRESHOLD = 5.hours

      attr_reader :parent, :data, :entry_point

      # Public: Create a scoped installation record with associated
      # permissions.
      #
      # parent  - IntegrationInstallation: The fully installed GitHub App
      #           installation with access to repositories etc.
      # data    - Hash: keys and values describing the access to be granted to
      #           the scoped installation. Full example:
      #           {
      #             "repositories" => [
      #               {
      #                 "id" => 123,
      #                 "permissions" => { "metadata" => "read", "packages" => "write" },
      #                 "pull_requests" => [
      #                   { "number" => 456, "permissions" => { "sarifs" => "write" } }
      #                 ],
      #                 "workflow_runs" => [
      #                   { "id" => 789, "permissions" => { "codespaces_prebuild" => "write" } }
      #                 ]
      #               },
      #             ],
      #           }
      # entry_point - Symbol: The call site initiating a scoped installation
      #               record creation. Used to trace writes to the permissions cluster.
      def self.perform(parent, data, entry_point:)
        new(parent, data, entry_point: entry_point).perform
      end

      def self.perform_with_cache(parent, data, entry_point:)
        new(parent, data, entry_point: entry_point).perform_with_cache
      end

      def initialize(parent, data, entry_point:)
        @parent      = parent
        @data        = data
        @entry_point = entry_point
      end

      def perform
        GitHub.tracer.in_span("ScopedIntegrationInstallation::Creators::Actions#perform", kind: :internal) do |_span|
          validate_permissions!

          create_record!
          grant_permissions

          @scoped_installation.instrument_creation

          GitHub.dogstats.increment("scoped_integration_installation.create", tags: ["result:success", "version:2"])
          Result.success(@scoped_installation)
        rescue Result::Error => e
          ActiveRecord::Base.connected_to(role: :writing) do
            @scoped_installation&.destroy
          end

          GitHub.dogstats.increment("scoped_integration_installation.create", tags: ["result:failed", "version:2"])
          Result.failed e.message
        end
      end

      def perform_with_cache
        GitHub.tracer.in_span("ScopedIntegrationInstallation::Creators::Actions#perform_with_cache", kind: :internal) do |_span|
          cache = ::ScopedIntegrationInstallation::Cache.new(CACHE_NAMESPACE, parent, data)

          if cache.exist?
            if (installation = cache.get) && valid_permissions? && !installation.expired?
              extend_expires_at(installation)
              result = Result.success(installation, found_cached: true)
              cache.set(result)
              return result
            end
          end

          result = perform
          cache.set(result)
        end
      end

      # Packages Permissions Availability TODO: If possible, we should rename this permission row to better reflect what it is about.
      def self.organization_packages_permission_row(target:, installation:, action:, expires_at: nil, ar_attributes: false)
        # TODO: Remove this when create we create Target based permissions for packages.
        # Grant the Organization/organization_packages permission for all User type targets.
        subject = IntegrationInstallation::AbilityCollection.new(
          parent: target,
          name: "organization_packages",
          ability_type_prefix: "Organization"
        )

        ::ScopedIntegrationInstallation::Creator.permission_row(installation, subject, action, expires_at, ar_attributes)
      end

      private

      # Overides ScopedIntegrationInstallation::Creators::Base#expires?
      # Actions scoped installation tokens always expire.
      def expires?
        true
      end

      def remaining_expiry_tag_prefix
        "scoped_integration_installation_actions"
      end

      def create_record!
        @scoped_installation = ActiveRecord::Base.connected_to(role: :writing) do
          ScopedIntegrationInstallation.create!(parent: parent, expires_at: expires_at)
        end
      end

      def grant_permissions
        rows = []
        highest_packages_action = T.let(nil, T.nilable(String))
        capable_of_managing_packages = Apps::Internal.capable?(:manage_packages_permissions, app: integration)

        repositories.each do |repository|
          repo_hash = data["repositories"].find do |repo|
            repo["id"] == repository.id || repo["name"] == repository.name
          end

          next unless repo_hash

          rows.concat(permission_rows_for_repository(repository, repo_hash["permissions"]))
          rows.concat(permission_rows_for_pull_requests(@scoped_installation, repository, repo_hash))
          rows.concat(permission_rows_for_workflow_runs(@scoped_installation, repository, repo_hash))

          packages_action = repo_hash.dig("permissions", "packages")

          if packages_action
            # highest_packages_action can be nil
            if T.must(Permission.actions[packages_action]) >= T.unsafe(Permission).actions[highest_packages_action].to_i
              highest_packages_action = packages_action
            end
          end
        end

        if highest_packages_action && capable_of_managing_packages
          rows << self.class.organization_packages_permission_row(
            target: target,
            installation: @scoped_installation,
            action: highest_packages_action,
            expires_at: expires_at
          )
        end

        begin
          permissions_attrs = rows.flatten

          ::Permissions::Service.grant_permissions!(
            permissions_attrs,
            stats_key: "scoped_integration_installation",
            entry_point: entry_point
          )
        rescue ActiveRecord::ActiveRecordError => err
          Failbot.report(err)
          raise Result::Error, ::ScopedIntegrationInstallation::Permissions::Result::HUMAN_READABLE_REASONS[:failed_to_write_permissions]
        end
      end

      def integration
        return @integration if defined?(@integration)
        @integration = parent.integration
      end

      def permission_rows_for_repository(repository, permissions)
        Repository::Resources.filter(permissions).map do |resource, action|
          subject_type = "#{Repository::Resources.parent_type}/#{resource}"
          subject = ::Permissions::Service::PseudoSubject.new(ability_id: repository.id, ability_type: subject_type)

          ::ScopedIntegrationInstallation::Creator.permission_row(
            @scoped_installation,
            subject,
            action,
            expires_at
          )
        end
      end

      memoize def target
        parent.target
      end

      memoize def repositories
        ids   = []
        names = []

        data["repositories"].each do |repo|
          # JSON schema guarantees that we will either
          # have a name or ID for each repository provided.
          if repo.key?("id")
            ids << repo["id"]
          else
            names << repo["name"]
          end
        end

        return [] if ids.empty? && names.empty?

        # Check to see if duplicate entries have been sent by id or name.
        if ids.uniq.size != ids.size || names.uniq.size != names.size
          raise Result::Error, ::ScopedIntegrationInstallation::Permissions::Result::HUMAN_READABLE_REASONS[:duplicate_repositories_selected]
        end

        repos_by_ids = T.let([], T::Array[Integer])
        repos_by_names = T.let([], T::Array[String])

        ids.in_groups_of(1_000, false) do |ids_batch|
          repos_by_ids += target.repositories.where(id: ids_batch).select(:id, :name).to_a
        end

        names.in_groups_of(1_000, false) do |names_batch|
          repos_by_names += target.repositories.where(name: names_batch).select(:id, :name).to_a
        end

        if repos_by_ids.intersect?(repos_by_names)
          raise Result::Error, ::ScopedIntegrationInstallation::Permissions::Result::HUMAN_READABLE_REASONS[:duplicate_repositories_selected]
        end

        repos = repos_by_ids + repos_by_names
        requested_count = ids.count + names.count

        # If we find a different number of repositories than what
        # was provided go ahead and fail out.
        if requested_count != repos.count
          raise Result::Error, ::ScopedIntegrationInstallation::Permissions::Result::HUMAN_READABLE_REASONS[:repositories_not_available_to_target]
        end

        repos
      end

      # Private: Take the list of repositories and converge all of the requested
      # permissions into a single Hash.
      #
      # Example:
      #
      # [
      #   { "id" => 1, "permissions" => { "metadata" => "read", "contents" => "read" } },
      #   { "name" => "dotfiles", "permissions" => { "metadata" => "read", "contents" => "write" } }
      # ]
      #
      # => { "metadata" => "read", "contents" => "write" }
      #
      # Returns a Hash.
      def repository_permissions
        return @repository_permissions if defined?(@repository_permissions)

        @repository_permissions = data["repositories"].each_with_object({}) do |repo, hash|
          hash.merge!(repo["permissions"]) do |_resource, action1, action2|
            Permission.actions[action1].to_i > Permission.actions[action2].to_i ? action1 : action2
          end
        end

        @repository_permissions = @repository_permissions.transform_values!(&:to_sym)
      end

      def validate_permissions!
        validate_repository_permissions!
        validate_pull_request_permissions!
        validate_workflow_run_permissions!
      end

      def validate_workflow_run_permissions!
        GitHub.tracer.in_span("ScopedIntegrationInstallation::Creators::Actions#validate_workflow_run_permissions") do
          resources = []
          actions = []

          data["repositories"].each do |repo_hash|
            return unless repo_hash.key?("workflow_runs")

            ids = repo_hash["workflow_runs"].map { |workflow_run| workflow_run["id"] }

            if ids.uniq.length != ids.length
              raise Result::Error, "There is at least one workflow run that has multiple entries"
            end

            repo_hash["workflow_runs"].each do |workflow_run|
              resources.concat workflow_run["permissions"].keys
              actions.concat workflow_run["permissions"].values
            end
          end

          resources.uniq!
          actions.uniq!

          return unless resources.any?
          parent_permissions = parent.permissions_or_cached_permissions

          unless parent_permissions.key?("actions")
            raise(Result::Error, MISSING_ACTIONS_ACCESS)
          end

          unless (resources - ::Actions::WorkflowRun::Resources.subject_types).empty?
            raise(Result::Error, ::ScopedIntegrationInstallation::Permissions::Result::HUMAN_READABLE_REASONS[:invalid_resource])
          end

          current_access = Permission.actions[parent_permissions["actions"]]
          validate_actions_privilege!(current_access, actions)
        end
      end

      def validate_actions_privilege!(current_access, actions)
        actions.each do |action|
          action = Permission.actions[action.to_sym]

          # Are they asking for a valid action (read/write/admin)?
          if action.nil?
            raise Result::Error, ::ScopedIntegrationInstallation::Permissions::Result::HUMAN_READABLE_REASONS[:invalid_action]
          end

          # Make sure we're not escalating privilege.
          if action > current_access
            raise(Result::Error, ::ScopedIntegrationInstallation::Permissions::Result::HUMAN_READABLE_REASONS[:permissions_upgraded])
          end
        end
      end

      def validate_pull_request_permissions!
        GitHub.tracer.in_span("ScopedIntegrationInstallation::Creators::Actions#validate_pull_request_permissions", kind: :internal) do |_span|
          resources = []
          actions   = []

          data["repositories"].each do |repo_hash|
            next unless repo_hash.key?("pull_requests")

            # Make sure each pull request is unique
            numbers = repo_hash["pull_requests"].map { |pull| pull["number"] }

            if numbers.uniq.length != numbers.length
              raise(Result::Error, "There is at least one pull request that has multiple entries")
            end

            repo_hash["pull_requests"].each do |pull_hash|
              resources.concat(pull_hash["permissions"].keys)
              actions.concat(pull_hash["permissions"].values)
            end
          end

          resources.uniq!
          actions.uniq!

          return unless resources.any?
          parent_permissions = parent.permissions_or_cached_permissions

          unless parent_permissions.key?("pull_requests")
            raise(Result::Error, MISSING_PULL_REQUEST_ACCESS)
          end

          # Does the resource they are requesting exist?
          unless (resources - PullRequest::Resources.subject_types).empty?
            raise(Result::Error, ::ScopedIntegrationInstallation::Permissions::Result::HUMAN_READABLE_REASONS[:invalid_resource])
          end

          current_access = Permission.actions[parent_permissions["pull_requests"]]
          validate_actions_privilege!(current_access, actions)
        end
      end

      def validate_repository_permissions!
        GitHub.tracer.in_span("ScopedIntegrationInstallation::Creators::Actions#validate_repository_permissions", kind: :internal) do |_span|
          check = ScopedIntegrationInstallation::Permissions.check(
            installation: parent,
            repositories: repositories,
            action:       :create,
            permissions:  repository_permissions,
          )

          raise(Result::Error, check.error_message) unless check.permitted?
        end
      end
    end
  end
end
