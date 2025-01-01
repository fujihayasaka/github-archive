# typed: false
# frozen_string_literal: true

module Search
  module Filters

    # The RegistryFilter is critical for ensuring that users only see the
    # private packages they are allowed to see.
    #
    # The RegistryFilter extends the RespositoryFilter. This gives the
    # Registry filter the ability to get a list of private repositories
    # that the current user has access to. The information is stored in
    # the `bool_collection` variable in either the `should` or `must` block
    # depending on the context of the search (global scoped versus scoped
    # to a user or org, for example).
    #
    # The package permissions can be broken into 3 distinct categories
    #
    # * V1
    # * V2
    # * Common - shared between v1 and v2
    #
    # Those rules are enumerated below (the code is the source of truth)
    #
    # Common: Anyone is allowed to see packages where `public` is true.
    #
    # V1 packages (inherit permissions from their associated repository)
    # * Package has a repo_id in the list of private repos from the repository filter
    #
    # V2 packages are subject to a more complicated set of permissions which requires
    # the use of the new enumeration API from authzd, as well as additional fields
    # from the record
    #
    # Private Packages
    # * User is an org admin of the org in which the namespace is
    # * User name is the same as the package namespace
    # * User ID is the author ID of the package
    # * User is explicity granted access to a package via UserRole
    # * Org based permissions
    #
    # Internal Packages
    # * Internal visibility and user is associated with an org via direct or business transient relation

    class RegistryFilter < ::Search::Filters::RepositoryFilter
      def initialize(opts = {})
        @owner_id                = opts.fetch(:owner_id, nil)
        @only_deleted_packages   = opts.fetch(:only_deleted_packages, false)
        @excluded_packages       = opts.fetch(:excluded_packages, [])

        super(opts)
      end

      # Package type filter is handled in the query by via qualifiers
      def must
        must = []
        must << { exists: { field: "versions" } } unless @only_deleted_packages

        # Repo ID is a subset of what an owner ID would return, so we don't need the less restrictive condition
        if !global_scoped_query?
          must << { terms: { repo_id: @repo_ids } } if repo_scoped_query?

          shoulds = []
          v2_shoulds = v2_filters << { term: { public: true } }

          v2_musts = []
          v2_musts << { terms: { owner_id: @owner_ids } } if owner_scoped_query?

          v2_bool = {
            bool: {
              must: v2_musts,
              should: v2_shoulds,
              minimum_should_match: 1
            }
          }

          shoulds << v2_bool

          if bool_collection.must.present? && !bool_collection.must.empty?
            v1_bool = {
              bool: {
                must: [
                  build_term_filter(field, bool_collection.must)
                ],
                must_not: [
                  { exists: { field: "owner_id" } }
                ]
              }
            }

            shoulds << v1_bool
          end

          must << {
            bool: {
              should: shoulds
            }
          }
        end

        if @only_deleted_packages
          must << { exists: { field: "deleted_at" } }
          must << {
            range: {
              deleted_at: {
                gte: "now-30d",
                lt: "now"
              }
            }
          }
        end

        must
      end

      def must_not
        must_not = []

        must_not << { exists: { field: "deleted_at" } } unless @only_deleted_packages
        must_not << { terms: { "original_name.raw" => @excluded_packages } } unless @excluded_packages.empty?

        must_not
      end

      # This is only used by RegistryPackageQuery. Along with
      # `minimum_should_match: true` the resulting query effectively applies
      # an OR logic to each of the conditions in the array.
      def should
        shoulds = [
          { term: { public: true } }
        ]

        return shoulds unless can_search_private_repositories_for_user?

        # V1
        shoulds.concat(v1_filters)

        # V2
        shoulds.concat(v2_filters)

        shoulds
      end

      def global_scoped_query?
        !owner_scoped_query? && !repo_scoped_query?
      end

      def v1_filters
        filters = []
        filters << build_term_filter(field, bool_collection.should) if global_scoped_query? && bool_collection.should.present? && !bool_collection.should.empty?
        filters << build_term_filter(:business_id, accessible_business_ids) if user_has_businesses?
        filters
      end

      def v2_filters
        return [] unless @current_user

        filters = []

        filters << { terms: { _id: package_ids } }

        # User is author of package
        filters << {
          bool: {
            must: [
              { term: { author_type: 0 } },
              { term: { author_id: @current_user.id } }
            ]
          }
        }

        # User name is the same as the package namespace
        user_logins = [@current_user.display_login, @current_user.display_login.downcase].uniq
        if GitHub.multi_tenant_enterprise? && (current_tenant = GitHub::CurrentTenant.get)
          user_logins = user_logins.map { |login| login["_"] ? login : "#{login}_#{current_tenant.slug}"  }
        end
        filters << build_term_filter(:namespace, user_logins)

        namespaces = fetch_namespaces

        # Package is administered by user
        filters << { terms: { namespace: namespaces[:admin] } } unless namespaces[:admin].empty?

        # Package in internal namespace
        filters << {
          bool: {
            must: [
              { match: { visibility: { query: "internal" } } },
              { terms: { namespace: namespaces[:internal] } }
            ]
          }
        } unless namespaces[:internal].empty?

        if owner_scoped_query? && owner_is_org?
          private_repos = []
          private_repos = private_repos.concat(bool_collection.should) if bool_collection.should.present?
          private_repos = private_repos.concat(bool_collection.must) if bool_collection.must.present?
          private_repos = private_repos.uniq

          # Repo based permissions
          filters << {
            bool: {
              must: [
                build_term_filter(field, private_repos),
                { term: { inherit_repo_permissions: true } }
              ]
            }
          } unless private_repos.empty?

        end

        filters
      end

      private

      # Get the internal namespaces for a user
      def fetch_namespaces
        return {} unless @current_user

        begin
          internal_namespaces = @current_user.organizations.pluck(:display_login)
          internal_namespaces += Organization.joins(:business_membership).where(business_membership: { business_id: @current_user.businesses.pluck(:id) }).pluck(:display_login)
          lowercase_namespaces = internal_namespaces.map { |n| n.downcase }
          if GitHub.multi_tenant_enterprise? && (current_tenant = GitHub::CurrentTenant.get)
            internal_namespaces = internal_namespaces.map { |n| n["_"] ? n : "#{n}_#{current_tenant.slug}" }
            lowercase_namespaces = lowercase_namespaces.map { |n| n["_"] ? n : "#{n}_#{current_tenant.slug}" }
          end
          internal_namespaces = internal_namespaces.concat(lowercase_namespaces).uniq
        rescue NoMethodError, ActiveRecord::RecordNotFound => e
          internal_namespaces = []
          GitHub.dogstats.increment("search.packages.filter.internal_namespaces.error")
        end

        begin
          admin_namespaces = Organization.where(id: @current_user.owned_organization_ids).pluck(:display_login).uniq
          lowercase_namespaces = admin_namespaces.map { |n| n.downcase }
          if GitHub.multi_tenant_enterprise? && (current_tenant = GitHub::CurrentTenant.get)
            admin_namespaces = admin_namespaces.map { |n| n["_"] ? n : "#{n}_#{current_tenant.slug}" }
            lowercase_namespaces = lowercase_namespaces.map { |n| n["_"] ? n : "#{n}_#{current_tenant.slug}" }
          end
          admin_namespaces = admin_namespaces.concat(lowercase_namespaces).uniq
        rescue NoMethodError, ActiveRecord::RecordNotFound => e
          admin_namespaces = []
          GitHub.dogstats.increment("search.packages.filter.admin_namespaces.error")
        end

        {
          internal: internal_namespaces,
          admin: admin_namespaces
        }
      end

      # The package IDs provided by the Authzd enumeration API for packages
      def package_ids
        return [] unless @current_user
        package_ids = fetch_package_ids(@current_user.id)
        package_ids.map! { |id| "rms-#{id}" }
      end

      # Scope helpers
      def owner_scoped_query?
        @owner_ids ||= provided_owner_ids
        !@owner_ids.empty?
      end

      def repo_scoped_query?
        @repo_ids ||= provided_repo_ids
        !@repo_ids.empty?
      end

      def user_has_businesses?
        @current_user && accessible_business_ids.any?
      end

      def owner_is_org?
        return false unless @owner_id.present?

        begin
          user = User.find(@owner_id)
          user&.type == "Organization"
        rescue NoMethodError, ActiveRecord::RecordNotFound => e
          GitHub.dogstats.increment("search.packages.filter.owner.id.error")
          false
        end
      end

      def provided_owner_ids
        owner_ids = []
        owner_ids << @owner_id if @owner_id.present?
        user_logins = []
        user_logins.concat qualifiers[:user].must if qualifiers[:user].must.present?
        user_logins.concat qualifiers[:org].must if qualifiers[:org].must.present?
        user_logins.concat qualifiers[:owner].must if qualifiers[:owner].must.present?
        owner_ids.concat User.where(login: user_logins).map { |u| u&.id } unless user_logins.compact.empty?
        owner_ids.uniq
      end

      def provided_repo_ids
        repo_ids = []
        repo_ids << @repo_id if @repo_id.present?
        repo_ids.concat repository_ids_from_repo(qualifiers[:repo].must) unless qualifiers[:repo].must&.empty?
        repo_ids.uniq
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

      def fetch_package_ids(user_id)
        authzd_req = Authzd::Enumerator::ForActorRequest.new(
          actor_id: user_id, actor_type: "User", subject_type: "Package",
          options: Authzd::Enumerator::Options.new(scope: :all, relationship: :read))
        response = Authzd.enumerator_client.for_actor(authzd_req)

        if response.error.present?
          GitHub.dogstats.increment("search.packages.filter.authzd.enum.error")
          return []
        end

        Array(response.data&.result_ids)
      end
    end  # RegistryPackagesFilter
  end  # Filters
end  # Search
