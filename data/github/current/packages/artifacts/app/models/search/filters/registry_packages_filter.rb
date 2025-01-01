# typed: true
# frozen_string_literal: true

module Search
  module Filters

    # The RepositoryFilter is critical for ensuring that users only see the
    # private packages they are allowed to see. Anyone is allowed to see
    # packages where `public` is true.
    #
    # V1 packages inherit permissions from their associated repository
    # so we use the repository filter which performs database queries and
    # returns a list of private repository IDs the user is allowed to see.
    # This list is used as a terms filter against the `repo_id` field.
    #
    # V2 packages do not inherit permissions from a repository so we return
    # all results and rely on the registry-metadata service to perform
    # authorization checks before displaying results to users.
    class RegistryPackagesFilter < ::Search::Filters::RepositoryFilter
      def initialize(opts = {})
        @owner_id                = opts.fetch(:owner_id, nil)
        @package_type            = opts.fetch(:package_type, nil)
        @only_deleted_packages   = opts.fetch(:only_deleted_packages, false)
        @excluded_packages       = opts.fetch(:excluded_packages, [])

        super(opts)
      end

      # Internal: Determine whether private repositories can be included in the
      # query. Private repositories can only be included if we have a currently-
      # logged-in user. If we're performing the query for an OAuth request,
      # then we also need 'read:packages' scope in order to search the user's accessible
      # packages in private repositories.
      #
      # Returns true if the list of accessible repositories should be determined
      #   based on the permissions of +current_user+. Returns false if only
      #   public repositories are accessible.
      def can_search_private_repositories_for_user?
        return false unless current_user
        return false if current_user.using_auth_via_integration?

        Api::AccessControl.scope?(current_user, "read:packages")
      end

      def must
        if @only_deleted_packages
          [
            {
              bool: {
                should: [
                  build_term_filter(field, bool_collection.must),
                  build_term_filter(:owner_id, @owner_id)
                ]
              }
            },
            deleted_at_filter,
            deleted_at_range_filter
          ]
        else
          if @repo_id.present?
            # Query is scoped to a repository.
            Array.wrap(build_term_filter(field, bool_collection.must))
          elsif @owner_id.present? & !bool_collection.must?
            # Query is scoped to an owner but owner has no repos. We drop
            # the repo term and only look for v2 packages which do not
            # require a repo to be associated.
            registry_metadata_filter
          end
        end
      end

      def must_not
        filters = []
        filters << deleted_at_filter unless @only_deleted_packages
        filters << excluded_packages_filter if @excluded_packages.any?
        filters.compact
      end

      # This is only used by RegistryPackageQuery. Along with
      # `minimum_should_match: true` the resulting query effectively applies
      # an OR logic to each of the conditions in the array.
      def should
        if bool_collection.must?
          # Query is scoped to an owner and owner has repos. Look for
          # repo owned packages and user owned packages by using an OR.
          # Evaluates to:
          #
          # ((repo_id in ?) OR (owner_id = ? AND package_type = ?)
          [
            build_term_filter(field, bool_collection.must),
            {
              bool: {
                must: registry_metadata_filter
              }
            }
          ]
        elsif bool_collection.should?
          # This is a global query and the viewer has private repositories.
          # Include repo_ids that viewer has access to.
          [
            {
              bool: {
                should: [
                  { term: { public: true } },
                  build_term_filter(:business_id, accessible_business_ids),
                  build_term_filter(field, bool_collection.should),
                ].compact,
              }
            },
            {
              bool: {
                must: registry_metadata_filter
              }
            }
          ]
        elsif current_user && accessible_business_ids.any?
          # This is a global query and the viewer has no private repositories.
          [
            {
              bool: {
                should: [
                  { term: { public: true } },
                  build_term_filter(:business_id, accessible_business_ids),
                ],
              }
            },
            {
              bool: {
                must: registry_metadata_filter
              }
            }
          ]
        else
          # Global query catchall. Only public results are returned.
          { term: { public: true } }
        end
      end

      # Filter hash for packages stored in the `registry-metadata` service
      def registry_metadata_filter
        owner_id = if @repo_id
          ::Repositories::Public.find_active!(@repo_id).owner
        elsif invalidate_private_profile_searches? && @owner_id && owner = User.find_by(id: @owner_id)
          owner.private_profile_for?(current_user) ? nil : @owner_id
        elsif @owner_id
          @owner_id
        end

        # Namespaces may be either a username or org name. Combine both qualifiers into an array to filter
        namespaces = Array.wrap(qualifiers[:org].must) + Array.wrap(qualifiers[:user].must)

        owner_id_term = owner_id ? { term: { owner_id: owner_id } } : { term: { public: true } }

        [
          owner_id_term,
        ].tap do |filters|
          filters << build_term_filter(:package_type, @package_type) if @package_type
          filters << { terms: { namespace: namespaces } } unless namespaces.empty? || !owner_id.nil?
          filters << build_term_filter(:repo_id, @repo_id) if @repo_id
        end
      end

      private

      def deleted_at_filter
        build_exists_filter(:deleted_at)
      end

      def deleted_at_range_filter
        {
          range: {
            deleted_at: {
              gte: "now-30d",
              lt: "now"
            }
          }
        }
      end

      def excluded_packages_filter
        {
          terms: {
            "original_name.raw" => @excluded_packages
          }
        }
      end

      def invalidate_private_profile_searches?
        FeatureFlag.vexi.enabled?(:invalidate_private_profile_searches, default: false) || FeatureFlag.vexi.enabled?(:invalidate_private_profile_searches, current_user, default: false)
      end
    end  # RegistryPackagesFilter
  end  # Filters
end  # Search
