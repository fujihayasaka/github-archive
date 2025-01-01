# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Gist < Platform::Objects::Base
      include GitHub::UTF8

      description "A Gist."

      implements_node templates: [[:g, :user_id, :repo_name]], as: "G", allow_nil_for: [:user_id], ready_date: Platform::Helpers::GlobalId::COHORT_4, uses_database_id: false do |gist|
        {
          prefix: :g,
          user_id: gist.user_id, # There's an `anonymous_gist_creation_enabled` config which allows this to be `nil` sometimes.
          repo_name: gist.repo_name,
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, gist)
        gist.async_user.then do |owner|
          org = owner.is_a?(::Organization) ? owner : nil
          permission.access_allowed?(:get_gist, resource: gist, current_org: org, current_repo: nil,
                                     allow_integrations: false, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.spam_check(object)
      end

      scopeless_tokens_as_minimum

      implements Interfaces::Starrable
      implements Interfaces::AbuseReportable
      implements Interfaces::UniformResourceLocatable

      created_at_field

      updated_at_field

      field :url, Scalars::URI, description: "The HTTP URL for this Gist.", method: :path_uri,
        null: false

      field :pushed_at, Scalars::DateTime, description: "Identifies when the gist was last pushed to.", null: true

      field :name, String, method: :repo_name, description: "The gist name.", null: false

      field :description, String, description: "The gist description.", null: true

      field :is_public, Boolean, method: :public?, description: "Whether the gist is public or not.", null: false

      field :is_fork, Boolean, "Identifies if the gist is a fork.", method: :fork?, null: false

      field :owner, Interfaces::RepositoryOwner, method: :async_user, description: "The gist owner.", null: true

      field :sha, String, description: "The gist's git sha.", null: true,
        visibility: :under_development

      field :comments, resolver: Resolvers::GistComments , description: "A list of comments associated with the gist"

      field :forks, resolver: Resolvers::GistForks , description: "A list of forks associated with the gist" do
        argument :order_by, Inputs::GistOrder, "Ordering options for gists returned from the connection", required: false
      end

      def self.load_from_next_global_id(parsed_id)
        Loaders::ActiveRecord.load(::Gist, parsed_id.parts[:repo_name], column: :repo_name)
      end

      def self.load_from_global_id(gist_repo_name)
        Loaders::ActiveRecord.load(::Gist, gist_repo_name, column: :repo_name)
      end

      field :is_pinned, Boolean, visibility: :under_development, null: false,
        description: "Returns whether this gist is pinned to the profile of the specified repository owner." do
        argument :profile_owner_id, ID, "The ID of the owner of the profile you want to check.",
          required: true
      end

      def is_pinned(profile_owner_id:)
        profile_owner = Helpers::NodeIdentification.
          typed_object_from_id([Interfaces::ProfileOwner], profile_owner_id, @context)
        Platform::Loaders::IsPinnedGist.load(
          profile_owner_id: profile_owner.id,
          gist_id: @object.id
        )
      end

      def stargazer_count
        Platform::Loaders::GistStargazerCount.load(@object, viewer: @context[:viewer])
      end

      field :title, String, visibility: :internal, description: "A short summary of this gist", null: true

      def title
        title = @object.description.presence ||
        @object.files.first&.name.presence ||
        @object.sha ||
        @object.name

        utf8(title)
      end

      field :stafftools_info, Objects::GistStafftoolsInfo, visibility: :internal,
        description: "Gist information only visible to site admin", null: true

      def stafftools_info
        return nil unless site_admin_for_stafftools?
        Models::GistStafftoolsInfo.new(@object)
      end

      field :files, [Objects::GistFile, null: true], description: "The files in this gist.", null: true do
        argument :limit, Integer, "The maximum number of files to return.", default_value: 10, required: false
        argument :oid, Scalars::GitObjectID, "The oid of the files to return", required: false
      end

      def files(limit:, oid: nil)
        if limit > ::Gist::MAX_FILES
          raise Errors::ArgumentLimit, "You can only fetch up to #{::Gist::MAX_FILES} files."
        end

        tree_entries = ::Gist.limit_files(@object.files(oid), limit)
        tree_entries.map { |tree_entry| Platform::Models::GistFile.new(@object, tree_entry) }
      end

      def self.load_from_params(params)
        Objects::User.load_from_params(params).then do |user|
          user && Loaders::ActiveRecord.load(::Gist.is_not_disabled.where(user_id: user.id), params[:gist_id], column: :repo_name)
        end
      end

      private def site_admin_for_stafftools?
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(context[:viewer], self.class.name)
      end
    end
  end
end
