# typed: false
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryAction < Platform::Objects::Base
      include OcticonsHelper
      include Scientist

      description "A action defined on a repository."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, action)
        if action.is_a?(Hash)
          # These are hard-coded in ::RepositoryAction for special uses
          action[:ghost_action] || action[:docker_action]
        else
          action.async_repository.then do |repo|
            result = permission.typed_can_access?("Repository", repo)
          end
        end
      end


      visibility :internal

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      minimum_accepted_scopes ["public_repo"]

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, action)
        if action.is_a?(Hash)
          # These are hard-coded in ::RepositoryAction for special uses
          action[:ghost_action] || action[:docker_action]
        else
          action.async_repository.then do |repo|
            repo.async_organization.then do |_org|
              permission.belongs_to_repository(action)
            end
          end
        end
      end

      global_id_field :id, description: "The Node ID of the RepositoryAction object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject
      database_id_field(visibility: :internal)

      field :name, String, "The name of the action.", null: false
      field :description, String, "The description of the action.", null: true
      field :featured, Boolean, "Is the action featured on the marketplace?", null: false
      field :rank_multiplier, Float, "Ranking of the Action. Higher places this Action higher on Marketplace and Workflow editor.", null: false
      field :path, String, "The path to where the action lives.", null: false
      field :icon_name, String, "The name of the icon to display.", null: true
      field :icon_color, String, "The color to display the action's icon.", null: true
      field :color, String, "The color to display with the action.", null: true
      field :base_path, String, "The directory containing the action.", null: false
      field :slug, String, "The slug of the action. Only available if it's listed on the Marketplace.", null: true
      field :security_email, String, "Internal GitHub use only. Email contact for getting in touch with the Action's owner.", null: true, visibility: :internal
      field :is_listed, Boolean, description: "Is the action listed on the Marketplace?", method: :listed?, null: false
      field :has_verified_owner, Boolean, description: "Is the owner of this Action verified?", method: :async_verified_owner?, null: false
      field :repository, Objects::Repository, "The repository that owns the action.", method: :async_repository, null: false

      field :action_runs, Connections.define(Objects::RepositoryActionRun), visibility: :internal,
        description: "All runs of this action.", null: true, connection: true do
      end

      field :uses_path_prefix, String, "The path prefix for the 'uses' value to use the action.", method: :external_uses_path_prefix, null: false

      field :readme, Scalars::HTML, "The HTML rendering of action repo's README.", null: true do
        argument :tag_name, String, "The tag name of version of the README to get.", required: false, default_value: ""
      end

      field :categories, [Objects::MarketplaceCategory],
        "A collection of all Marketplace categories that describe this action.",
        null:       false,
        visibility: :internal,
        method:     :async_categories

      field :regular_categories, [Objects::MarketplaceCategory],
        "A collection of non-filter Marketplace categories that describe this action.",
        null:       false,
        visibility: :internal,
        method:     :async_regular_categories

      field :filter_categories, [Objects::MarketplaceCategory],
        "A collection of filter-type Marketplace categories that describe this action.",
        null:       false,
        visibility: :internal,
        method:     :async_filter_categories

      url_fields description: "The HTTP URL for the Marketplace listing." do |action_listing|
        template = Addressable::Template.new("/marketplace/actions/{slug}")
        template.expand slug: action_listing.slug
      end

      field :releases, Connections.define(Objects::Release), description: "List of releases for this action.", null: false, connection: true do
        argument :order_by, Inputs::ReleaseOrder, "Order for connection", required: false
        argument :published, Boolean, "Whether or not the releases should be published ones", required: false, default_value: false
      end

      field :latest_release, Objects::Release, description: "The latest published release of this action.", null: true do
        argument :published, Boolean, "Whether or not the latest release should be a published one.", required: false, default_value: false
      end

      field :release, Objects::Release, description: "Look up a release based on given criteria", null: true do
        argument :tag_name, String, "The tag name of the release", required: true
      end

      def action_runs(**arguments)
        @object.action_runs.scoped
      end

      def security_email
        return @object.security_email if @object.security_email

        @object.async_repository.then do |repo|
          repo.async_owner.then do |owner|
            owner.async_primary_user_email.then do |primary_email|
              primary_email && primary_email.email
            end
          end
        end
      end

      def readme(tag_name:)
        @object.async_repository.then do |repo|
          repo.async_default_branch.then do |branch|
            committish = tag_name.presence || branch

            @object.async_readme(committish: committish).then do |file|
              if file.present?
                context = {
                  entity: repo,
                  blob: file,
                  name: file.path,
                  anchor_icon: octicon("link"),
                  path: File.dirname(file.path),
                  committish: committish,
                }

                GitHub::Goomba::MarkupPipeline.to_html(file, context)
              end
            end
          end
        end
      end

      def releases(**arguments)
        scope = arguments[:published] ? @object.published_releases : @object.releases

        if order_by = arguments[:order_by]
          scope = scope.order("releases.#{order_by[:field]} #{order_by[:direction]}")
        end

        scope
      end

      def latest_release(**arguments)
        releases = arguments[:published] ? @object.published_releases : @object.releases
        releases.latest.first
      end

      def release(**arguments)
        @object.releases.find_by_tag_name(arguments[:tag_name])
      end
    end
  end
end
