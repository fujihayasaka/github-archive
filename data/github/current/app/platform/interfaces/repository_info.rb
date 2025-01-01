# typed: false
# frozen_string_literal: true

module Platform
  module Interfaces
    # NOTE: This interface has a security-related purpose too.
    # The fields on this interface are visible to staff users when
    # they use the `Query.staffAccessedRepository` field (via stafftools, for example).
    #
    # That field returns private repos, under the assumption that only _some_ fields
    # will actually be returned to the staff member.
    #
    # This interface serves as an allowlist of fields which are visible to
    # staff members when they load a private repository in stafftools.
    module RepositoryInfo
      include Platform::Interfaces::Base
      description "A subset of repository info."

      field :name, String, "The name of the repository.", null: false

      url_fields(description: "The HTTP URL for this repository") { |repository| repository.path_uri }

      field :description, String, "The description of the repository.", null: true

      field :description_html, Scalars::HTML, description: "The description of the repository rendered to HTML.", null: false

      field :short_description_html, Scalars::HTML, description: "A description of the repository, rendered to HTML without any links in it.", null: false do
        argument :limit, Integer, "How many characters to return.", default_value: 200, required: false
      end

      def short_description_html(**arguments)
        @object.async_short_description_html(limit: arguments[:limit])
      end

      field :open_graph_image, Objects::RepositoryImage, visibility: :internal,
        null: true, description: "The image used to represent this repository in Open Graph data.",
        method: :async_open_graph_image

      field :uses_custom_open_graph_image, Boolean, null: false,
        description: "Whether this repository has a custom image to use with Open Graph as " \
                     "opposed to being represented by the owner's avatar.",
        method: :async_uses_custom_open_graph_image?

      field :open_graph_image_url, Scalars::URI, null: false,
        description: "The image used to represent this repository in Open Graph data."

      def open_graph_image_url
        @object.async_open_graph_image_url(viewer: context[:viewer])
      end

      field :show_enhanced_og_image, Boolean,
        description: "Whether this repository should use the enhanced open graph image URL",
        visibility: :internal,
        method: :show_enhanced_og_image?,
        null: false

      field :homepage_url, Scalars::URI, "The repository's URL.", method: :homepage, null: true

      field :is_private, Boolean, "Identifies if the repository is private or internal.", method: :private?, null: false

      field :visibility, Enums::RepositoryVisibility, "Indicates the repository's visibility level.", null: false, method: :async_visibility

      field :has_anonymous_access_enabled, Boolean, "Indicates if the repository has anonymous Git read access feature enabled.", method: :anonymous_git_access_enabled?, null: false do
        visibility :internal, environments: [:dotcom]
        visibility :public, environments: [:enterprise]
      end

      field :is_anonymous_access_available, Boolean, visibility: :internal, description: "Indicates if anonymous git access is available for the repository", method: :anonymous_git_access_available?, null: false

      field :is_archived, Boolean, "Indicates if the repository is unmaintained.", method: :archived?, null: false

      field :is_fork, Boolean, "Identifies if the repository is a fork.", method: :fork?, null: false

      field :fork_count, Integer, "Returns how many forks there are of this repository in the whole network.", method: :forks_count, null: false

      field :is_locked, Boolean, "Indicates if the repository has been locked or not.", method: :locked?, null: false

      field :is_trade_controls_read_only, Boolean, "Indicates if the repositories plan owner is trade controls restricted, which makes this repo behave as archived", method: :trade_controls_read_only?, null: false, visibility: :internal

      field :lock_reason, Enums::RepositoryLockReason, "The reason the repository has been locked.", null: true

      def lock_reason
        @context[:permission].async_can_get_full_repo?(@object).then do |can_get_full_repo|
          if can_get_full_repo
            @object.lock_reason
          else
            nil
          end
        end
      end

      field :has_issues_enabled, Boolean, "Indicates if the repository has issues feature enabled.", method: :has_issues?, null: false

      field :has_report_to_maintainer_enabled, Boolean, visibility: :under_development, description: "Indicates if the repository has the report to maintainer feature enabled.", method: :tiered_reporting_explicitly_enabled?, null: false

      field :has_wiki_enabled, Boolean, "Indicates if the repository has wiki feature enabled.", method: :has_wiki?, null: false

      field :has_restricted_wiki_editing, Boolean, "Indicates if a repository has wiki editing restricted to pushers only.", visibility: :under_development, method: :wiki_access_to_pushers, null: false

      field :is_in_organization, Boolean, "Indicates if a repository is either owned by an organization, or is a private fork of an organization repository.", method: :async_in_organization?, null: false

      field :has_projects_enabled, Boolean, description: "Indicates if the repository has the Projects feature enabled.", method: :async_has_projects_enabled?, null: false

      field :has_downloads, Boolean, "Indicates if the repository has downloads.", method: :has_downloads?, visibility: :internal, null: false

      field :has_pages, Boolean, visibility: :internal, description: "Indicates if the repository has Pages configured.", null: false

      def has_pages
        @object.async_page.then do
          @object.page.present?
        end
      end

      field :has_discussions_enabled,
        Boolean,
        description: "Indicates if the repository has the Discussions feature enabled.",
        method: :async_discussions_active?,
        null: false

      field :has_sponsorships_enabled,
        Boolean,
        description: "Indicates if the repository displays a Sponsor button for financial contributions.",
        method: :async_repository_funding_links_explicitly_enabled?,
        null: false,
        visibility: {
          internal: { environments: [:enterprise] },
          public: { environments: [:dotcom] },
        }

      created_at_field

      updated_at_field

      field :pushed_at, Scalars::DateTime, "Identifies the date and time when the repository was last pushed to.", null: true

      field :archived_at, Scalars::DateTime, "Identifies the date and time when the repository was archived.", null: true

      field :license_info, Objects::License, description: "The license associated with the repository", null: true

      def license_info
        @object.async_repository_license.then do
          @object.license
        end
      end

      field :license_contents, String, "Contents of the license file in the repository", required_capabilities: [:mobile_only_schema_mask], null: true

      def license_contents
        @object.async_repository_license.then do
          next unless @object.license

          @object.async_preferred_license.then do |tree|
            tree.try(:data)
          end
        end
      end

      field :is_template, Boolean, null: false, method: :template?,
        description: "Identifies if the repository is a template that can be used to generate " \
                     "new repositories."

      field :is_mirror, Boolean, description: "Identifies if the repository is a mirror.", null: false

      def is_mirror
        @object.async_mirror.then do |mirror|
          mirror ? true : false
        end
      end

      field :mirror_url, Scalars::URI, description: "The repository's original mirror URL.", null: true

      def mirror_url
        @object.async_mirror.then do |mirror|
          mirror.try(:url)
        end
      end

      field :owner, Interfaces::RepositoryOwner, method: :async_owner, description: "The User owner of the repository.", null: false

      field :name_with_owner, String, description: "The repository's name with owner.", null: false, resolver_method: :async_name_with_owner_for_api
      def async_name_with_owner_for_api
        @object.async_owner.then do
          @object.name_with_owner_for_api(use: context[:serialize_login])
        end
      end

      field :permalink, Scalars::URI, visibility: :internal, description: "The permalink for this repository", null: false do
        argument :include_host, Boolean, "Whether or not to include the hostname or only the path information", required: false
      end

      def permalink(**arguments)
        Addressable::URI.parse(@object.permalink(include_host: arguments[:include_host]))
      end

      field :two_factor_requirement_met_by, Boolean, visibility: :internal, description: "2FA requirement met by viewing user", null: false

      def two_factor_requirement_met_by
        if @context[:viewer]
          @object.async_two_factor_requirement_met_by?(@context[:viewer])
        else
          false
        end
      end

      # TODO: define_url_field should be used here but doesn't yet support arguments
      #   When that method is updated, this definition should be migrated which will
      #   automatically add the corresponding definition for commitsUrl
      field :commits_resource_path, Scalars::URI, visibility: :internal, description: "The HTTP URL pointing to this repository's commits listing.", null: false do
        argument :author, String, "The login of a user by which to filter the repository's commits.", required: false
      end

      def commits_resource_path(**arguments)
        @object.async_commits_path_uri(author: arguments[:author])
      end

      field :network_count, Integer, "Returns how many repositories there are in this network.", visibility: :internal, null: false

      def network_count
        Loaders::ActiveRecordAssociation.load(@object, :network).then do
          @object.network_count
        end
      end

      field :no_index, Boolean, visibility: :internal, method: :async_noindex?, description: "Returns whether or not a repository has been de-indexed by Google", null: false

      field :is_hidden_from_discovery, Boolean, visibility: :internal, method: :async_is_hidden_from_discovery?, description: "Returns whether or not a repository has been hidden from discovery pages", null: false

      field :default_branch, String, visibility: :internal, description: "The repository's default branch.", null: false

      def default_branch
        @object.async_network.then do
          @object.default_branch
        end
      end

      field :require_login, Boolean, visibility: :internal, method: :async_require_login?, description: "Returns whether or not a repository requires a login to view content", null: false

      field :require_opt_in, Boolean, visibility: :internal, method: :async_require_opt_in?, description: "Returns whether or not a repository requires an opt-in to view content", null: false

      field :collaborators_only, Boolean, visibility: :internal, method: :async_collaborators_only?, description: "Returns whether or not a repository is restricted to collaborators only", null: false
    end
  end
end
