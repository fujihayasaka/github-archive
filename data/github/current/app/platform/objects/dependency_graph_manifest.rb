# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class DependencyGraphManifest < Platform::Objects::Base
      include UrlHelper
      description "Dependency manifest for a repository"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, manifest)
        manifest.async_repository.then do |repo|
          permission.async_owner_if_org(repo).then do |org|
            permission.access_allowed?(:get_dependency_graph, repo: repo, resource: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        Loaders::ActiveRecord.load(::Repository, object.repository_id, security_violation_behaviour: :nil).then do |repo|
          repo&.resources.metadata.readable_by?(permission.viewer)
        end
      end

      minimum_accepted_scopes ["public_repo"]

      visibility :public

      field :filename, String, "Fully qualified manifest filename", null: false

      field :blob_path, String, "Path to view the manifest file blob", null: false
      def blob_path
        @object.async_repository.then do |repo|
          repo.async_network.then do |_network|
            blob_view_path(@object.filename, repo.default_branch, repo)
          end
        end
      end

      field :parseable, Boolean, "Were we able to parse the manifest?", method: :parseable?, null: false

      field :exceeds_max_size, Boolean, "Is the manifest too big to parse?", method: :exceeds_max_size?, null: false

      field :repository, Objects::Repository, description: "The repository containing the manifest", null: false, method: :async_repository

      field :dependencies_count, Integer, "The number of dependencies listed in the manifest", null: true

      field :dependencies, Connections.define(Objects::DependencyGraphDependency), null: true,
        connection: false, # We're implementing connections by hand instead
        description: "A list of manifest dependencies" do
          T.bind(self, Platform::Objects::Base::Field::ManualConnectionArguments)
          has_connection_arguments
        end

      def dependencies(**arguments)
        @object.async_repository.then do |repo|
          if @object.exceeds_max_size? # If the manifest is too big to be parsed we can't fetch anymore
            ConnectionWrappers::ArrayWrapper.new(
              ArrayWrapper.new(@object.dependencies),
              first: arguments[:first],
              last: arguments[:last],
              before: arguments[:before],
              after: arguments[:after],
              arguments: arguments,
              parent: object,
              context: context,
            )
          else
            first = arguments[:first]
            after = arguments[:after]
            prefer = repo.repository_vulnerability_alerts.affected_package_names

            # If we already loaded the dependencies we need we can just return them
            if @object.dependencies_filter[:first] == first && @object.dependencies_filter[:after] == after
              arguments[:page_info] = @object.dependencies_page_info
              ConnectionWrappers::ManifestDependenciesConnection.new(
                @object.dependencies,
                first: arguments[:first],
                last: arguments[:last],
                before: arguments[:before],
                after: arguments[:after],
                arguments: arguments,
                parent: object,
                context: context,
              )
            else
              manifest = ::DependencyGraph::ManifestsQuery.new(
                manifest_filter: {
                  repository_id: @object.repository_id,
                  manifest_id: @object.id.to_i,
                  preview: repo.dependency_graph_preview?,
                },
                dependencies_filter: {
                  first: first,
                  after: after,
                  prefer: prefer,
                },
                include_dependencies: true,
              ).results.value![:manifests]&.first

              if manifest
                arguments[:page_info] = manifest.dependencies_page_info
                ConnectionWrappers::ManifestDependenciesConnection.new(
                  manifest.dependencies,
                  first: arguments[:first],
                  last: arguments[:last],
                  before: arguments[:before],
                  after: arguments[:after],
                  arguments: arguments,
                  parent: object,
                  context: context,
                )
              else
                # This is an empty connection:
                ConnectionWrappers::ArrayWrapper.new(
                  ArrayWrapper.new,
                  first: arguments[:first],
                  last: arguments[:last],
                  before: arguments[:before],
                  after: arguments[:after],
                  arguments: arguments,
                  parent: object,
                  context: context,
                )
              end
            end
          end
        end
      end

      field :viewer_can_view_alerts, Boolean, "Can the viewer view vulnerability alerts in this manifest?", null: false, visibility: :internal
      def viewer_can_view_alerts
        object.async_repository.then do |repo|
          repo.async_owner.then do
            repo.vulnerability_alerts_visible_to?(@context[:viewer])
          end
        end
      end

      implements_node templates: [[:dgm, :repo_id, :id]], as: "DGM", ready_date: Platform::Helpers::GlobalId::COHORT_3 do |dep_graph_manifest|
        dep_graph_manifest.async_repository.then do |repo|
          {
            prefix: :dgm,
            repo_id: repo.id,
            id: dep_graph_manifest.id
          }
        end
      end

      def self.load_from_next_global_id(parsed_id)
        load_dependency_graph_manifest(parsed_id.parts[:repo_id], parsed_id.parts[:id])
      end

      def self.load_from_global_id(id)
        repository_id, manifest_identifier = id.split(":", 2)
        load_dependency_graph_manifest(repository_id.to_i, manifest_identifier)
      end

      def self.load_dependency_graph_manifest(repository_id, manifest_identifier)
        Loaders::ActiveRecord.load(::Repository, repository_id, security_violation_behaviour: :nil).then do |repo|
          if repo.present?
            manifest_id = manifest_identifier.to_i
            # Pass `preview: true` because we don't have access to the
            # current user to perform a `preview_features?` check. This
            # should be fine since we don't expect users without preview
            # access to ever to obtain global IDs for manifests in preview.
            # If a user hacks the global ID, it's okay to expose preview
            # data because the data is not sensitive, just potentially
            # incomplete.
            Platform::Loaders::Manifest.load(repository_id, manifest_id, preview: true)
          end
        end
      end
    end
  end
end
