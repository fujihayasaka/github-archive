# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryAdvisory < Platform::Objects::Base
      description "A maintainer advisory for dependents of a repository"
      minimum_accepted_scopes ["public_repo"]

      mobile_only true

      implements_node templates: [[:rra, :repo_id, :repository_advisory_id, :ghsa_id]], as: "REPA", ready_date: Platform::Helpers::GlobalId::COHORT_4, uses_database_id: false do |repository_advisory|
        {
          prefix: :rra,
          repo_id: repository_advisory.repository_id,
          repository_advisory_id: repository_advisory.id,
          ghsa_id: repository_advisory.ghsa_id
        }
      end

      implements Interfaces::Comment
      implements Interfaces::MayBeInternal
      implements Interfaces::Reactable
      implements Interfaces::UniformResourceLocatable
      implements Interfaces::Updatable
      implements Interfaces::UpdatableComment

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, security_advisory)
        # this check is only here for SAML enforcement (side
        # effect of `access_allowed` via `current_org`), but it's
        # skipped for the media cards service in public repos
        permission.async_repo_and_org_owner(security_advisory).then do |repo, org|
          accessing_public_repo_from_custom_og_image?(permission, repo) || permission.access_allowed?(
            :saml_via_graphql, # returns false
            resource: security_advisory,
            current_org: org,
            current_repo: repo,
            allow_integrations: false,
            allow_user_via_granular_actor: false)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.load_repo_and_owner(object).then do
          object.readable_by?(permission.viewer)
        end
      end

      def self.load_from_next_global_id(parsed_id)
        Loaders::ActiveRecord.load(::RepositoryAdvisory, parsed_id.parts[:ghsa_id], column: :ghsa_id)
      end

      def self.load_from_global_id(ghsa_id)
        Loaders::ActiveRecord.load(::RepositoryAdvisory, ghsa_id, column: :ghsa_id)
      end

      database_id_field

      url_fields description: "The URL for this advisory" do |advisory|
        advisory.async_path_uri
      end

      field :ghsa_id, String, "The GitHub Security Advisory ID", null: false
      field :title, String, "The plaintext title of the advisory", null: false
      field :description, String, "A plaintext description of the advisory", null: false
      field :comments, Connections.define(Objects::RepositoryAdvisoryComment), "The advisory discussion comments", null: false

      field :state, Platform::Enums::RepositoryAdvisoryState, "The current state of the advisory", null: false, visibility: :internal
      field :advisory_published_at, Scalars::DateTime, "When the advisory was published", null: true, method: :published_at, visibility: :internal
      field :publisher, Objects::User, "The user who published the advisory", null: true, method: :async_publisher, visibility: :internal
      field :severity, Enums::RepositoryAdvisorySeverity, "The severity of the advisory", null: false, visibility: :internal
      field :packages, Connections.define(Objects::RepositoryAdvisoryPackage), "The packages affected by this advisory", null: false, method: :affected_products, visibility: :internal

      # Interfaces::Comment

      # It's not possible to create the initial "comment" of a repository
      # advisory via email.
      def created_via_email
        false
      end

      # For a repository advisory the publish time is the actual time of publication
      # and not when the advisory was created (like a standard comment is).
      def published_at
        @object.published_at
      end

      # Interfaces::MayBeInternal

      # The initial repository advisory body is always written before
      # advisory publication, so it should always be internal.
      def is_internal
        true
      end

      def self.accessing_public_repo_from_custom_og_image?(permission, repo)
        return false unless permission.integration
        custom_og_image_app = Apps::Privileged.integration(:opengraph)
        return false unless custom_og_image_app
        return false unless permission.integration == custom_og_image_app
        return false unless repo&.public?

        true
      end
    end
  end
end
