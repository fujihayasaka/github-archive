# typed: true
# frozen_string_literal: true

module Api
  class SerializerOptions
    class << self
      def from(options)
        github_options.from(options)
      end

      def fill(options)
        github_options.fill(options)
      end

      private

      def github_options
        @github_options ||= GitHub::Options.new(
          :accept_mime_types,
          :after_id,
          :assets,
          :comment_counts,
          :current_user,
          :current_integration,
          :default_branch,
          :detail,
          :diff,
          :emails,
          :exclude, # for migrations
          :etag,
          :exclude_email,
          :exclude_parent,
          :exclude_pull_requests, # for workflows
          :files,
          :full,
          :highlight,
          :hook,
          :include_mentions,
          :include_timestamps,
          :include_repository,
          :issues,
          :last_modified,
          :list,
          :global_id_selection,
          :max_age,
          :merged,
          :mime_params,
          :page,
          :path,
          :per_page,
          :plan,
          :private,
          :owner_private,
          :profile,
          :public_key,
          :pusher,
          :ref,
          :release,
          :repo,
          :repositories,
          :route,
          :sha,
          :show_merge_settings,
          :generate_temp_clone_token,
          :simple,
          :summary,
          :team,
          :url,
          :user,
          :version,
          :repo_path,
          :force, # for Media::Blobs
          :origin,
          :token,
          :license,
          :html_url,
          :business_plus, # remove after Business ship
          :code_of_conduct, # code_of_conduct preview
          :env, # Rack environment for request
          :include_values, # Repo config preview
          :pem, # For integration_hash after app creation
          :secret, # For integration_hash after app creation
          :filter_project_events, # For project event details
          :search,
          :permissions, # For token responses
          :single_file, # For token responses
          :has_multiple_single_files, # For token responses
          :single_file_paths, # For token responses
          :repository_selection, # For token responses
          :installation, # For token responses
          :resolvers, # For code scanning responses
          :serialize_login, # For internal service payloads in multi-tenant environments
          :skip_strict_loading,
          :show_template_repository,
          :api_version, # For API versioning
          :show_security_settings, # For displaying extra security details
          :show_repo_security_settings, # For displaying extra security details
          :show_security_feature_auto_enablement_settings, # For displaying org level security feature auto enablement settings
          :user_permissions, # for collaborator hash
          :user_roles, # for collaborator hash
          :permissions_added, # For Personal Access Token Request hash
          :permissions_upgraded, # For Personal Access Token Request hash
          :permissions_result, # For Personal Access Token Request hash
          :expires_at, # For Personal Access Token Request hash
          :expired, # For Personal Access Token Request hash
          :valid_after, # For [site] scoped installation tokens
          :repo_advisory_writable, # For Repository Advisory hash
          :removed_pvr_author, # For Repository Advisory hash
          :request_source, # For repository ruleset hash,
          :created, # for copilot seats
          :staff_authorized, # whether or not a staff memeber is authorized to view the resource
          :exporting_ruleset, # whether or not the call is being made to export a ruleset
          :evaluation_result, # For repository rule suite hash
          :include_issue_type, # For issue hash
          :check_email_claimed, # Whether or not to check if EMU email is claimed
          # cache object to allow serializers to store and retrieve hashes within the scope of the current request
          #
          # each key within object represents a different hash, to allow for more flexibility without duplicating
          # a new key each time
          :object_cache,
        ) do
          include SerializerOptionsMimeTypes
        end
      end
    end
  end
end
