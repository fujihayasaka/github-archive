# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Release < Platform::Objects::Base
      description "A release contains the content for a release."

      implements_node templates: [[:rr, :repo_id, :release_id]], allow_nil_for: [:release_id], as: "RE", ready_date: Platform::Helpers::GlobalId::COHORT_2 do |release|
        {
          prefix: :rr,
          repo_id: release.repository_id,
          release_id: release.id
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, release)
        permission.async_repo_and_org_owner(release).then do |repo, org|
          permission.access_allowed?(:get_release, repo: repo, resource: release, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_repository(object)
      end

      scopeless_tokens_as_minimum

      implements Interfaces::UniformResourceLocatable
      implements Interfaces::Trigger
      implements Interfaces::Reactable

      field :name, String, "The title of the release.", null: true
      field :description, String, "The description of the release.", method: :body, null: true

      field :repository, Objects::Repository, description: "The repository that the release belongs to.", null: false, method: :async_repository

      field :description_html, Scalars::HTML, description: "The description of this release rendered to HTML.", null: true

      def description_html
        @object.async_body_html.then do |body_html|
          body_html || GitHub::HTMLSafeString::EMPTY
        end
      end

      field :short_description_html, Scalars::HTML, description: "A description of the release, rendered to HTML without any links in it.", null: true do
        argument :limit, Integer, "How many characters to return.", default_value: 200, required: false
      end

      def short_description_html(**arguments)
        @object.async_short_description_html_info(length: arguments[:limit]).then do |info|
          info[:html]
        end
      end

      url_fields description: "The HTTP URL for this issue" do |release|
        release.async_repository.then do |repository|
          repository.async_owner.then do |_owner|
            release.permalink(include_host: false)
          end
        end
      end

      field :tag_name, String, description: "The name of the release's Git tag", null: false, method: :exposed_tag_name
      field :tag, Ref, description: "The Git tag the release points to", null: true

      def tag
        @object.async_repository.then do |repository|
          repository.async_network.then do
            @object.tag
          end
        end
      end

      field :published_at, Scalars::DateTime, "Identifies the date and time when the release was created.", null: true

      def published_at
        @object.published_at if @object.published?
      end

      created_at_field

      updated_at_field

      field :is_prerelease, Boolean, "Whether or not the release is a prerelease", method: :prerelease, null: false

      field :is_draft, Boolean, "Whether or not the release is a draft", method: :draft?, null: false

      field :is_latest, Boolean, "Whether or not the release is the latest releast", method: :is_latest?, null: false

      def is_latest
        @object.async_repository.then do |repository|
          repository.async_network.then do
            @object.is_latest?(@context[:viewer])
          end
        end
      end

      field :author, Objects::User, "The author of the release", null: true

      def author
        @object.async_author.then do |author|
          next unless author
          @context[:permission].typed_can_see?("User", author).then do |can_read|
            can_read && !author.hide_from_user?(@context[:viewer]) ? author : nil
          end
        end
      end

      field :mentions, Connections.define(Objects::User), null: true,
          description: "A list of users mentioned in the release description"

      field :release_assets, Connections.define(Objects::ReleaseAsset), description: "List of releases assets which are dependent on this release.", null: false, connection: true do
        argument :name, String, "A name to filter the assets by.", required: false
      end

      def release_assets(**arguments)
        if arguments[:name]
          @object.release_assets.scoped.where(name: arguments[:name])
        else
          @object.release_assets.scoped
        end
      end

      field :package_versions, Connections.define(Objects::PackageVersion), resolver: Resolvers::PackageVersions, description: "List of packages associated with this release.", visibility: :internal, null: false, connection: true

      field :is_published_on_marketplace, Boolean, description: "Whether or not the release is for a GitHub Action published on the Marketplace.", null: false, visibility: :internal

      def is_published_on_marketplace
        @object.async_repository_action_release.then do |repository_action_release|
          if repository_action_release
            repository_action_release.published_on_marketplace?
          else
            false
          end
        end
      end

      field :tag_commit, Objects::Commit, method: :async_tag_commit, description: "The tag commit for this release.", null: true

      field :discussion, Objects::Discussion, method: :async_discussion, description: "The linked discussion for this release", required_capabilities: [:mobile_only_schema_mask], null: true

      field :repository_action, Objects::RepositoryAction, method: :async_repository_action, description: "The GitHub Action for this release.", null: true, visibility: :internal

      def self.load_from_global_id(id)
        Loaders::ActiveRecord.load(::Release, id.to_i)
      end

      def self.load_from_params(params)
        Objects::Repository.load_from_params(params).then do |repo|
          Loaders::ReleaseByTagName.load(repo, params[:name]).then do |release|
            release
          end
        end
      end
    end
  end
end
