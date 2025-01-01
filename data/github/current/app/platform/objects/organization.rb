# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Organization < Platform::Objects::Base
      include Objects::Base::RecordObjectAccess
      include GitHub::ResilienceMixin

      description "An account on GitHub, with one or more owners, that has repositories, members and teams."

      # TODO This needed `allow_nil_for: [:id]` because some Hydro instrumentation
      # tries to build Global IDs for non-persisted objects. Try removing that config,
      # and fix any broken tests to make sure that Hydro instrumentation will still work
      implements_node templates: [[:o, :id]], as: "O", allow_nil_for: [:id], ready_date: Platform::Helpers::GlobalId::COHORT_5 do |org|
        { prefix: :o, id: org.id }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, org)
        viewer_is_enterprise_owner = T.must(org).async_business.then do |business|
          if permission.viewer&.user? && business.present?
            business.adminable_by?(permission.viewer)
          end
        end

        bypass_policies = viewer_is_enterprise_owner.sync ? [:ip_allowlist, :external_conditional_access_policy] : [] # rubocop:disable GitHub/DontSyncInsideFields

        permission.access_allowed?(
          :read_org_public,
          resource: Platform::PublicResource.new(resource: org),
          current_repo: nil,
          current_org: nil,
          allow_integrations: true,
          allow_user_via_granular_actor: true,
          bypass_cap_policies: bypass_policies
        )
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_business.then do |business|
          if permission.external_request?
            if permission.authenticating_as_app? || permission.viewer&.site_admin?
              true
            elsif permission.viewer&.user? && business.present? && business.enterprise_managed?
              permission.viewer.enterprise_managed_business == business
            else
              # See if the org should be hidden for being spammy
              !object.hide_from_user?(permission.viewer)
            end
          else
            true # Return true for internal requests
          end
        end
      end

      minimum_accepted_scopes ["read:org"]

      implements Interfaces::Actor
      implements Interfaces::PackageOwner
      implements Interfaces::PackageSearch
      implements Interfaces::ProjectOwner
      implements Interfaces::ProjectV2Owner
      implements Interfaces::ProjectV2Recent
      implements Interfaces::RepositoryDiscussionAuthor
      implements Interfaces::RepositoryDiscussionCommentAuthor
      implements Interfaces::RepositoryOwner
      implements Interfaces::MarketplaceListingOwner
      implements Interfaces::UniformResourceLocatable
      implements Interfaces::Billable
      implements Interfaces::PlanOwner
      implements Interfaces::FeatureFlaggable
      implements Interfaces::MemberStatusable
      implements Interfaces::ProfileOwner
      implements Interfaces::Sponsorable

      database_id_field

      url_fields description: "The HTTP URL for this organization." do |org|
        org.permalink(include_host: false)
      end

      def total_available_seats
        @object.async_business.then do
          @object.total_available_seats
        end
      end

      field :oap_whitelist_required, Boolean, visibility: :internal, description: <<~DESCRIPTION, null: false do
          Whether an OAuth application listed in the Marketplace
          must be whitelisted before authorization.
        DESCRIPTION

        argument :listing_slug, String, "The slug of the MarketplaceListing", required: true
      end

      def oap_whitelist_required(**arguments)
        return false unless @object.restricts_oauth_applications?

        Loaders::ActiveRecord.load(::Marketplace::Listing, arguments[:listing_slug], column: :slug).then do |listing|
          if T.must(listing).listable_is_oauth_application?
            oauth_application = T.must(listing).async_listable.then do |oauth_application|
              !@object.allows_oauth_application?(oauth_application)
            end
          else
            false
          end
        end
      end

      field :audit_log, Connections.define(Unions::OrganizationAuditEntry),
        deprecated: Helpers::AuditLog::DeprecationNotice,
        description: "Audit log entries of the organization",
        null: false,
        connection: true do
          argument :query, String, "The query string to filter audit entries", required: false
          argument :order_by, Inputs::AuditLogOrder, "Ordering options for the returned audit log entries.", required: false,
            default_value: { field: "timestamp", direction: "DESC" }
        end

      def audit_log(**arguments)
        raise Errors::PlanNotSupported.new("Organization billing plan does not support access to auditLog information.") unless @object.plan_supports?(:audit_log_api)

        viewer_can_see = @object.can_read_org_audit_logs?(@context[:viewer]) && @context[:permission].can_access_audit_log_for_organization?(@object)

        raise Errors::Forbidden.new("#{@context[:viewer].display_login} does not have permission to retrieve auditLog information.") unless viewer_can_see

        # We override the index_name in the test environment because audit
        # entries are logged to `audit_log-test` locally or
        # [`audit_log-test`..`audit_log-test-15`] in CI. They do not follow
        # the date slicing logic used in production.
        index_name = Rails.env.test? ? "audit_log#{Elastomer.env.postfix}" : nil

        public_platform = false

        allowlist =
          if Platform::GlobalScope.origin_api?
            public_platform = true
            AuditLogEntry.public_platform_organization_action_names
          else
            AuditLogEntry.all_platform_organization_action_names
          end

        search_params = {
          current_user: @context[:viewer],
          direction: arguments[:order_by] && arguments[:order_by][:direction],
          index_name: index_name,
          org_id: @object.id,
          phrase: arguments[:query],
          allowlist: allowlist,
          limit_history: true,
          public_platform: public_platform,
          from_graphql: true,
        }

        # This will either return an Search::Queries::AuditLogQuery if feature flag is off
        # or an Audit::Driftwood::Query
        ::Audit::Driftwood::Query.new_org_business_query(search_params)
      end

      field :login, String, description: "The organization's login name.", null: false, resolver_method: :login_for_api
      def login_for_api
        @object.login_for_api(use: context[:serialize_login])
      end

      field :name, String, description: "The organization's public profile name.", null: true

      def name
        @object.async_profile.then do |profile|
          profile.nil? || profile.name.blank? ? @object.display_login : profile.name
        end
      end

      field :has_profile, Boolean, visibility: :internal, description: "Whether the organization has a public profile.", null: false

      def has_profile
        @object.async_profile.then do |profile|
          !!profile
        end
      end

      field :requires_two_factor_authentication, Boolean, description: "When true the organization requires all members, billing managers, and outside collaborators to enable two-factor authentication.", minimum_accepted_scopes: ["admin:org"], null: true

      def requires_two_factor_authentication
        org = @object
        if @context[:permission].can_view_two_factor_enabled?(org)
          org.two_factor_requirement_enabled?
        else
          raise Errors::Forbidden.new("#{@context[:viewer].display_login} does not have the right permission to retrieve requiresTwoFactorAuthentication information")
        end
      end

      field :description, String, description: "The organization's public profile description.", null: true

      def description
        @object.async_profile.then do |_profile|
          @object.profile_bio
        end
      end

      field :description_html, String, description: "The organization's public profile description rendered to HTML.", null: true

      def description_html
        @object.async_profile.then do |_profile|
          GitHub::Goomba::DescriptionPipeline.to_html(@object.profile_bio)
        end
      end

      field :company, String, visibility: :internal, description: "The organization's public profile company.", null: true

      def company
        @object.async_profile.then do |_profile|
          @object.profile_company
        end
      end

      field :website_url, Scalars::URI, description: "The organization's public profile URL.", null: true

      def website_url
        @object.async_profile.then do |_profile|
          @object.profile_blog
        end
      end

      field :twitter_username, String, description: "The organization's Twitter username.", null: true

      def twitter_username
        @object.async_profile.then do |profile|
          profile.try(:twitter_username)
        end
      end

      field :readme, Objects::RepositoryReadme, required_capabilities: [:mobile_only_schema_mask], description: "The organization's profile readme.",
        null: true

      def readme
        org_profile = @object.create_org_profile_readme(type: "public")
        org_profile.async_visible?.then do |is_visible|
          org_profile.readme if is_visible
        end
      end

      field :location, String, description: "The organization's public profile location.", null: true

      def location
        @object.async_profile.then do |_profile|
          @object.profile_location
        end
      end

      field :email, String, description: "The organization's public email.", null: true

      def email
        @object.async_profile.then do |_profile|
          @object.profile_email
        end
      end

      field :has_organization_projects_enabled, Boolean, visibility: :internal, method: :organization_projects_enabled?, description: "Whether the organization has projects enabled.", null: false

      field :has_repository_projects_enabled, Boolean, visibility: :internal, method: :repository_projects_enabled?, description: "Whether the organization has repository projects enabled.", null: false

      field :has_insights_enabled, Boolean, visibility: :internal, method: :insights_enabled?, description: "Whether the organization has insights enabled.", null: false

      field :organization_wide_projects_v2_role, Enums::ProjectV2Roles, feature_flag: :org_wide_projects_v2_role_mutation, resolver: Resolvers::OrganizationWideProjectsV2Role, description: "The organization-wide Projects V2 role.", null: false

      created_at_field

      updated_at_field

      field :archived_at, Scalars::DateTime, "Identifies the date and time when the organization was archived.", null: true

      field :viewer_is_billing_manager_only, Boolean, visibility: :under_development, null: true,
        description: <<~DESCRIPTION
          Check if the viewer's only relation to this organization is as its billing manager.
        DESCRIPTION

      def viewer_is_billing_manager_only
        @object.billing_manager_only?(@context[:viewer])
      end

      field :viewer_is_following, Boolean, description: "Whether or not this Organization is followed by the viewer.", null: false

      def viewer_is_following
        viewer = @context[:viewer]
        viewer && Loaders::IsFollowingCheck.load(viewer.id, @object.id)
      end

      field :organization_billing_email, String, description: "The billing email for the organization.", minimum_accepted_scopes: ["admin:org"], null: true

      def organization_billing_email
        accessible = @context[:permission].can_view_org_billing_email?(@object)

        return "" unless accessible

        Loaders::ActiveRecord.load(::Profile, @object.id, column: :user_id).then do |_profile|
          current_viewer = @context[:viewer]
          current_integratable = @context[:oauth_app] || @context[:integration]

          if current_viewer.present? && current_viewer.owned_organizations.include?(@object)
            @object.billing_email
          elsif current_integratable.present? && @object.enterprise_has_subscriptions?
            @object.async_enterprise_has_purchased_app?(current_integratable).then do |result|
              result ? @object.billing_email : nil
            end
          elsif current_integratable.present?
            @object.async_adminable_account_has_purchased_app?(current_integratable).then do |result|
              result ? @object.billing_email : nil
            end
          end
        end
      end

      field :avatar_url, Scalars::URI, description: "A URL pointing to the organization's public avatar.", null: false do
        argument :size, Integer, "The size of the resulting square image.", required: false
      end

      def avatar_url(**arguments)
        if GitHub.private_mode_enabled? && !GitHub.multi_tenant_enterprise? && Apps::Privileged.capable?(:enterprise_avatar_display, app: context[:oauth_app])
          "#{GitHub.api_url}/enterprise/avatars#{@object.primary_avatar_path}?s=#{arguments[:size]}"
        else
          @object.primary_avatar_url(arguments[:size])
        end
      end

      field :issuer, String, visibility: :internal, description: "A unique identifier for the Organization's SAML IdP", null: true

      def issuer
        Loaders::ActiveRecord.load(::Organization::SamlProvider, @object.id, column: :organization_id).then do |provider|
          provider.try(:issuer)
        end
      end

      field :idp_certificate, Scalars::X509Certificate, visibility: :internal, description: "The organization's IdP x509 certificate.", null: true

      def idp_certificate
        Loaders::ActiveRecord.load(::Organization::SamlProvider, @object.id, column: :organization_id).then do |provider|
          provider.try(:idp_certificate)
        end
      end

      # http://www.datypic.com/sc/ds/e-ds_SignatureMethod.html
      field :signature_method, Scalars::URI, visibility: :internal, description: "The signature algorithm used to sign SAML requests for an Organization's identity provider.", null: true

      def signature_method
        Loaders::ActiveRecord.load(::Organization::SamlProvider, @object.id, column: :organization_id).then do |provider|
          provider.try(:signature_method)
        end
      end

      # http://www.datypic.com/sc/ds/e-ds_DigestMethod.html
      field :digest_method, Scalars::URI, visibility: :internal, description: "The digest algorithm used to sign SAML requests for an Organization's identity provider.", null: true

      def digest_method
        Loaders::ActiveRecord.load(::Organization::SamlProvider, @object.id, column: :organization_id).then do |provider|
          provider.try(:digest_method)
        end
      end

      field :saml_identity_provider, Objects::OrganizationIdentityProvider,
            description: "The Organization's SAML identity provider. Visible to (1) organization owners,
              (2) organization owners' personal access tokens (classic) with read:org or admin:org scope,
              (3) GitHub App with an installation token with read or write access to members.".squish,
            null: true
      def saml_identity_provider
        Promise.all([
          object.async_business,
          object.async_saml_provider,
        ]).then do |business, saml_provider|
          next saml_provider if saml_provider.nil? || business.nil?

          business.async_saml_provider.then do |business_saml_provider|
            if business_saml_provider
              raise Errors::Forbidden.new("The Organization's SAML identity provider is disabled when an Enterprise SAML identity provider is available.")
            end

            saml_provider
          end
        end
      end

      field :external_identities, Connections.define(Objects::ExternalIdentity), visibility: :internal, description: "External Identities of organization members provisioned by the Identity Provider in effect for the organization (either its own, or its Enterprise's)", minimum_accepted_scopes: ["admin:org"], null: false do
        argument :members_only, Boolean, "If true, filter external identities with org membership, otherwise fetch all the external identities", required: false
      end

      def external_identities(members_only: false)
        # Currently restricted to integrations only (e.g. group-syncer)
        unless @context[:viewer] && @context[:viewer].try(:installation)
          return ::ExternalIdentity.none
        end
        Promise.all([
          @object.async_saml_provider,
          @object.async_business_saml_provider,
        ]).then do |org_provider, business_provider|
          scope =
            if business_provider
              # SAML configured at business level => get business SAML identities for members of the org
              # Business SAML takes precedence over org SAML, so ignore the Org SAML config, if it's present
              business_provider.external_identities_for_organization(@object)
            elsif org_provider
              # SAML configured at org level, and the org either doesn't belong to a business,
              # or the business doesn't have SAML configured => org member identities
              # Wrapped in a reading block to ensure that we aren't hitting the primary
              ActiveRecord::Base.connected_to(role: :reading) do
                ::ExternalIdentity.by_provider(org_provider)
              end
            else
              ::ExternalIdentity.none
            end

          scope = scope.where(user_id: @object.member_ids) if members_only

          scope
        end
      end

      field :ip_allow_list_enabled_setting,
        Enums::IpAllowListEnabledSettingValue,
        description: "The setting value for whether the organization has an IP allow list enabled.",
        null: false

      def ip_allow_list_enabled_setting
        accessible = object.adminable_by?(context[:viewer]) &&
          context[:permission].can_view_ip_allow_list_settings?(object)
        unless accessible
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have the right permission to retrieve ipAllowListEnabledSetting."
        end

        if object.ip_allowlist_enabled?
          T.must(Enums::IpAllowListEnabledSettingValue.values["ENABLED"]).value
        else
          T.must(Enums::IpAllowListEnabledSettingValue.values["DISABLED"]).value
        end
      end

      field :ip_allow_list_for_installed_apps_enabled_setting,
        Enums::IpAllowListForInstalledAppsEnabledSettingValue,
        description: "The setting value for whether the organization has IP allow list configuration for installed GitHub Apps enabled.",
        null: false

      def ip_allow_list_for_installed_apps_enabled_setting
        accessible = object.adminable_by?(context[:viewer]) &&
          context[:permission].can_view_ip_allow_list_settings?(object)
        unless accessible
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have the right permission to retrieve ipAllowListForInstalledAppsEnabledSetting."
        end

        if object.ip_allowlist_app_access_enabled?
          T.must(Enums::IpAllowListForInstalledAppsEnabledSettingValue.values["ENABLED"]).value
        else
          T.must(Enums::IpAllowListForInstalledAppsEnabledSettingValue.values["DISABLED"]).value
        end
      end

      field :ip_allow_list_entries, Connections.define(Objects::IpAllowListEntry),
        description: "The IP addresses that are allowed to access resources owned by the organization.",
        connection: true, null: false do
        argument :order_by, Inputs::IpAllowListEntryOrder,
          "Ordering options for IP allow list entries returned.",
          required: false, default_value: { field: "allow_list_value", direction: "ASC" }
      end

      def ip_allow_list_entries(order_by: nil)
        accessible = object.adminable_by?(context[:viewer]) &&
          context[:permission].can_view_ip_allow_list_settings?(object)
        unless accessible
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have the right permission to retrieve ipAllowListEntries."
        end

        Promise.all([object.async_business]).then do
          entries = ::IpAllowlistEntry.usable_for object

          unless order_by.nil?
            entries = entries.order "#{order_by[:field]} #{order_by[:direction]}"
          end

          entries
        end
      end

      field :admin_info, Objects::OrganizationAdminInfo, description: "Organization information only visible to admin", null: true

      def admin_info
        if @context[:viewer] && (@object.adminable_by?(@context[:viewer]) || @context[:viewer].site_admin?)
          Models::OrganizationAdminInfo.new(@object)
        else
          nil
        end
      end

      field :viewer_can_create_repositories, Boolean, description: "Viewer can create repositories on this organization", null: false

      def viewer_can_create_repositories
        @object.async_can_create_repository?(@context[:viewer])
      end

      field :viewer_can_create_teams, Boolean, description: "Viewer can create teams on this organization.", null: false

      def viewer_can_create_teams
        @object.can_create_team?(@context[:viewer])
      end

      field :viewer_is_a_member, Boolean, description: "Viewer is an active member of this organization.", null: false

      def viewer_is_a_member
        @object.direct_member?(@context[:viewer])
      end

      field :viewer_can_administer, Boolean, description: "Organization is adminable by the viewer.", null: false

      def viewer_can_administer
        @object.adminable_by?(@context[:viewer])
      end

      field :members_can_fork_private_repositories, Boolean, description: "Members can fork private repositories in this organization", null: false

      def members_can_fork_private_repositories
        can_view_repository_forking_setting = context[:permission].access_allowed?(
          :view_org_settings,
          resource: @object,
          current_org: @object,
          current_repo: nil,
          allow_integrations: true,
          allow_user_via_granular_actor: true
        )

        if can_view_repository_forking_setting
          @object.allow_private_repository_forking?
        else
          raise Errors::Forbidden.new(
            "#{context[:viewer].display_login} does not have the right permission to view membersCanForkPrivateRepositories."
          )
        end
      end

      field :organization_discussions_repository, Objects::Repository, required_capabilities: [:mobile_only_schema_mask], description: "Returns target repository if one is set for Org level Discussions", null: true

      def organization_discussions_repository
        @object.async_discussion_repository.then do |discussion_repo|
          discussion_repo&.async_repository
        end
      end

      field :has_team_discussions_enabled, Boolean, method: :async_team_discussions_allowed?, visibility: :internal, description: "Whether or not team discussions are enabled for this organization.", null: false

      field :stafftools_info, Objects::OrganizationStafftoolsInfo, visibility: :internal, description: "User information only visible to site admin", null: true

      def stafftools_info
        if self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          Models::AccountStafftoolsInfo.new(@object)
        else
          nil
        end
      end

      field :team, Objects::Team, description: "Find an organization's team by its slug.", null: true do
        argument :slug, String, "The name or slug of the team to find.", required: true
      end

      def team(slug:)
        if context[:permission].organization_credential_authorized_if_external_request?(@object, resource: @object)
          Loaders::TeamBySlug.load(@object, slug).then do |candidate_team|
            next unless candidate_team
            candidate_team.async_visible_to?(@context[:viewer]).then do |visible|
              candidate_team if visible
            end
          end
        end
      end

      field :migration, Objects::LegacyMigration, description: "Fetch a migration by GUID", feature_flag: :gh_migrator_import_to_dotcom, null: true do
        argument :guid, String, "The GUID of the migration to load", required: true
      end

      def migration(**arguments)
        if @object.adminable_by?(@context[:viewer])
          ::Migration.where(owner_id: @object.id, guid: arguments[:guid]).first
        end
      end

      field :admins, Connections::User, visibility: :internal, description: "A list of all of the admins for this organization", null: false, connection: true, exempt_from_spam_filter_check: true

      field :mannequins, Connections.define(Objects::Mannequin),
        description: "A list of all mannequins for this organization.",
        null: false,
        connection: true do
          argument :login, String, "Filter mannequins by login.", required: false

          argument :order_by, Inputs::MannequinOrder,
            "Ordering options for mannequins returned from the connection.",
            required: false,
            default_value: { field: "created_at", direction: "ASC" }
        end

      def mannequins(**arguments)
        @object.async_business.then do
          can_list_mannequins = context[:permission].access_allowed?(
            :octoshift_import,
            resource: @object,
            organization: @object,
            current_repo: nil
          )

          raise Errors::Forbidden.new(
            "#{context[:viewer].display_login} does not have the right permission to retrieve mannequins."
          ) unless can_list_mannequins

          if @object.adminable_by?(@context[:viewer])
            scope = @object.mannequins.scoped
            order_by = arguments[:order_by]

            if arguments[:login].present?
              scope = scope.where(source_login: arguments[:login])
            end

            scope.order("users.#{order_by[:field]} #{order_by[:direction]}")
          else
            ArrayWrapper.new([])
          end
        end
      end

      field :repository_migrations, Connections.define(Objects::RepositoryMigration),
        description: "A list of all repository migrations for this organization.",
        null: false,
        connection: false do # disable built-in connection wrapper because we're paginating ourselves.
          has_connection_arguments

          argument :state, Enums::MigrationState, "Filter repository migrations by state.", required: false
          argument :repository_name, String, "Filter repository migrations by repository name.", required: false
          argument :order_by, Inputs::RepositoryMigrationOrder,
              "Ordering options for repository migrations returned.",
              required: false,
              default_value: { field: :MIGRATION_ORDER_FIELD_CREATED_AT, direction: :MIGRATION_ORDER_DIRECTION_ASC }
        end

      def repository_migrations(**arguments)
        @object.async_business.then do
          can_list_migrations = context[:permission].access_allowed?(
            :octoshift_import,
            resource: @object,
            organization: @object,
            current_repo: nil
          )

          raise Errors::Forbidden.new(
            "#{context[:viewer].display_login} does not have the right permission to retrieve repository migrations."
          ) unless can_list_migrations

          Platform::ConnectionWrappers::RepositoryMigrations.new(
            @object,
            first: arguments[:first],
            last: arguments[:last],
            after: arguments[:after],
            before: arguments[:before],
            arguments: arguments,
            context: @context,
            field: @field
          )
        end
      end

      field :migration_archives,
        Connections.define(Objects::MigrationArchive),
        description: "Archives to be used for GitHub Enterprise Importer (GEI) migrations.",
        method: :octoshift_migration_archives,
        visibility: {
          public: { environments: [:dotcom, :enterprise] },
        },
        feature_flag: :octoshift_github_owned_storage,
        null: false,
        connection: true do
          argument :order_by, Inputs::MigrationArchiveOrder,
              "Ordering options for migration archives returned from the connection.",
              required: false,
              default_value: { field: "created_at", direction: "ASC" }
        end

      def migration_archives(order_by: nil)
        raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have the right permission to retrieve repository migration archives.") unless has_octoshift_import_auth?

        GitHub::PrefillAssociations.prefill_associations(object, [:octoshift_migration_archives])

        if order_by && order_by.field == "created_at" && order_by.direction == "DESC"
          object.octoshift_migration_archives.sort { |a, b| b.created_at <=> a.created_at }
        else
          object.octoshift_migration_archives.sort { |a, b| a.created_at <=> b.created_at }
        end
      end

      field :enterprise_owners,
        resolver: Resolvers::OrganizationEnterpriseOwners,
        description: "A list of owners of the organization's enterprise account.",
        connection: true

      field :members_with_role, resolver: Resolvers::OrganizationMembers, description: "A list of users who are members of this organization.", connection: true do
        argument :max_members_limit, Integer, visibility: :internal, description: "The maximum number of organization members to retrieve", required: false, default_value: 50000
        argument :phrase, String, visibility: :internal, description: "An optional search phrase to query for members across organizations", required: false, default_value: nil
      end

      field :teams, resolver: Resolvers::OrganizationTeams, description: "A list of teams in this organization.", connection: true

      field :eligible_parent_teams, Connections.define(Objects::Team), visibility: :internal, description: "List of eligible parent teams", null: false, connection: true do
        argument :query, String, "The query string to filter teams by name with", required: false
        argument :for_team, String, "Find eligible parents for this team", required: false
      end

      def eligible_parent_teams(**arguments)
        @object.parent_teams_search_for(arguments[:query], @context[:viewer], child_team_slug: arguments[:for_team])
      end

      field :is_viewer_blocked, Boolean, description: "Whether or not the viewer is blocked from the organization", null: true, required_capabilities: [:mobile_only_schema_mask]

      def is_viewer_blocked(**arguments)
        @object.ignore?(context[:viewer])
      end

      field :externally_managed_teams, Connections.define(Objects::Team), visibility: :internal, method: :async_externally_managed_teams, description: "The teams that have one or more external mappings.", null: false

      field :gists, resolver: Resolvers::Gists, visibility: :internal, description: "List of gists belonging to the organization.", connection: true

      url_fields prefix: :projects, description: "The HTTP URL listing organization's projects" do |org|
        template = Addressable::Template.new("/orgs/{login}/projects")
        template.expand login: org.display_login
      end

      field :pending_members, Connections::User,
        description: "A list of users who have been invited to join this organization.",
        minimum_accepted_scopes: ["admin:org"],
        null: false,
        connection: true

      def pending_members
        has_member_access = @object.member_or_can_view_members?(context[:viewer])
        can_list_members = context[:permission].access_allowed?(
          :v4_read_org_invitations, resource: @object, current_org: @object, current_repo: nil,
          allow_integrations: true, allow_user_via_granular_actor: true, raise_on_error: false
        )

        if has_member_access && can_list_members
          users = @object.pending_members
          users.filter_spam_for(context[:viewer])
        else
          ::User.none
        end
      end

      field :pending_collaborators, Connections::PendingCollaborator, "A list of users with pending collaborator invitations for this organization.", null: false, visibility: :internal do
        argument :is_occupying_seat, Boolean, "Optionally filter to show pending collaborators with invitations that occupy a seat.", required: false
        argument :query, String, "Optional query to search collaborators by login.", required: false
      end

      def pending_collaborators(**arguments)
        if @object.adminable_by?(@context[:viewer]) || @object.billing_manager?(@context[:viewer]) || @context[:viewer].site_admin?
          scope = @object.pending_collaborators

          if arguments[:is_occupying_seat] == true
            scope = scope.where(id: @object.private_repo_non_collaborator_invitee_ids)
          end

          if arguments[:query].present?
            query = ActiveRecord::Base.sanitize_sql_like(arguments[:query].strip)
            scope = scope.where(["users.login LIKE :query", { query: "%#{query}%" }])
          end

          scope.filter_spam_for(@context[:viewer])
        else
          ArrayWrapper.new([])
        end
      end

      field :pending_collaborator_invitations, Connections::RepositoryInvitation, null: false, visibility: :internal do
        description "The pending collaborator invitations for this organization."
        argument :is_occupying_seat, Boolean, "Optionally filter to show pending collaborators invitations that occupy a seat.", required: false, default_value: false
        argument :user_id, ID, "The ID of the user to optionally filter invitations for.", required: false
      end

      def pending_collaborator_invitations(**arguments)
        if @object.adminable_by?(@context[:viewer]) || @context[:viewer].site_admin?
          scope = @object.repository_invitations.scoped

          if arguments[:is_occupying_seat] == true
            scope = scope.where(invitee_id: @object.private_repo_non_collaborator_invitee_ids).or(
              scope.where(email: @object.private_repo_non_user_invited_emails - @object.pending_invited_non_user_emails)
            )
          end

          if arguments[:user_id]
            user = Helpers::NodeIdentification.typed_object_from_id([Objects::User], arguments[:user_id], @context)
            scope = scope.where(invitee_id: user.id)
          end
          scope
        else
          ArrayWrapper.new([])
        end
      end

      field :integration_installations, Connections.define(Objects::IntegrationInstallation), "A list of the org's installed GitHub Apps", visibility: :internal, null: false, connection: true do
        argument :include_subscriptions, Boolean, "Whether to include installations associated with a Marketplace subscription", required: false, default_value: true
        argument :include_marketplace_categories, [String], "Only return installations for apps that belong to a Marketplace listing that belongs to one of the specified categories.", required: false, default_value: []
        argument :exclude_marketplace_categories, [String], "Only return installations for apps that do not belong to a Marketplace listing that belongs to one of the specified categories.", required: false, default_value: []
      end

      def integration_installations(**arguments)
        if arguments[:include_marketplace_categories].any? && arguments[:exclude_marketplace_categories].any?
          raise Platform::Errors::Unprocessable.new("Arguments includeMarketplaceCategories and excludeMarketplaceCategories are incompatible.")
        end

        # exclude installations for non user-installable GitHub apps
        installations = @object.integration_installations.user_installable

        if !arguments[:include_subscriptions]
          installations = installations.where(subscription_item_id: nil)
        end

        if arguments[:include_marketplace_categories].any?
          installations = installations.
            joins("JOIN marketplace_listings ON integration_installations.integration_id=marketplace_listings.listable_id").
            joins("JOIN marketplace_categories_listings ON marketplace_categories_listings.marketplace_listing_id=marketplace_listings.id").
            joins("JOIN marketplace_categories ON (marketplace_categories.id=marketplace_categories_listings.marketplace_category_id AND marketplace_listings.listable_type = 'Integration')").
            merge(Marketplace::Listing.for_primary_category_only).
            where("marketplace_categories.slug IN (?)", arguments[:include_marketplace_categories])
        end

        if arguments[:exclude_marketplace_categories].any?
          installations = installations.
            joins("LEFT JOIN marketplace_listings ON integration_installations.integration_id=marketplace_listings.listable_id").
            joins("LEFT JOIN marketplace_categories_listings ON marketplace_categories_listings.marketplace_listing_id=marketplace_listings.id").
            joins("LEFT JOIN marketplace_categories ON (marketplace_categories.id=marketplace_categories_listings.marketplace_category_id AND marketplace_listings.listable_type = 'Integration')").
            where("marketplace_listings.id IS NULL OR marketplace_categories.slug NOT IN (?)", arguments[:exclude_marketplace_categories])
        end

        installations
      end

      field :domains, Connections.define(Objects::VerifiableDomain),
        description: "A list of domains owned by the organization.",
        null: true, connection: true do
        argument :is_verified, Boolean, "Filter by if the domain is verified.", required: false, default_value: nil
        argument :is_approved, Boolean, "Filter by if the domain is approved.", required: false, default_value: nil
        argument :order_by, Inputs::VerifiableDomainOrder,
          "Ordering options for verifiable domains returned.",
          required: false, default_value: { field: "domain", direction: "ASC" }
      end

      def domains(is_verified: nil, is_approved: nil, order_by: nil)
        accessible = \
          object.adminable_by?(context[:viewer]) && context[:permission].can_view_verifiable_domains?(object)
        unless accessible
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have the right permission to retrieve domains."
        end

        @object.async_business.then do
          scope = ::VerifiableDomain.usable_for(@object)

          if is_verified == true
            scope = scope.verified
          elsif is_verified == false
            scope = scope.unverified
          end

          unless order_by.nil?
            scope = scope.reorder "#{order_by[:field]} #{order_by[:direction]}"
          end

          scope
        end
      end

      field :notification_delivery_restriction_enabled_setting,
        Enums::NotificationRestrictionSettingValue,
        description: "Indicates if email notification delivery for this organization is restricted to verified or approved domains.",
        visibility: {
            public: { environments: [:dotcom, :enterprise] },
        },
        null: false

      def notification_delivery_restriction_enabled_setting
        accessible = object.adminable_by?(context[:viewer]) &&
          context[:permission].can_view_verifiable_domains?(object)
        unless accessible
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have the right permission to retrieve notificationDeliveryRestrictionEnabledSetting."
        end

        if object.restrict_notifications_to_verified_domains?
          T.must(Enums::NotificationRestrictionSettingValue.values["ENABLED"]).value
        else
          T.must(Enums::NotificationRestrictionSettingValue.values["DISABLED"]).value
        end
      end

      field :is_verified,
        Boolean,
        description: "Whether the organization has verified its profile email and website.",
        visibility: {
            public: { environments: [:dotcom, :enterprise] },
        },
        null: false,
        method: :async_is_verified?

      field :action_invocation_blocked, Boolean, "Indicates if action invocation is blocked for this organization", method: :action_invocation_blocked?, null: false, visibility: :internal

      field :enterprise, Objects::Enterprise, description: "The organization's enterprise account", visibility: :under_development, minimum_accepted_scopes: ["admin:org"], null: true

      def enterprise
        object.async_business.then do |business|
          if object.adminable_by?(context[:viewer]) || context[:viewer].site_admin? || business&.readable_by?(context[:viewer])
            business
          end
        end
      end

      field :pending_enterprise_invitations, Connections.define(Objects::EnterpriseOrganizationInvitation), description: "A list of pending invitations for this organization to join an enterprise", minimum_accepted_scopes: ["admin:org"], null: true, connection: true do
        visibility :under_development
        argument :enterprise_ids, [ID], "Enterprise IDs to filter invitations by", required: false
      end

      def pending_enterprise_invitations(enterprise_ids: nil)
        return unless object.adminable_by?(context[:viewer])

        invitations = object.business_invitations.pending

        if enterprise_ids&.any?
          businesses = enterprise_ids.map do |id|
            Helpers::NodeIdentification.typed_object_from_id(
              [Objects::Enterprise], id, @context
            )
          end

          invitations = invitations.where(business: businesses)
        end

        invitations
      end

      field :terms_of_service_type, Enums::OrganizationTermsOfServiceType, description: "The terms of service this organization has agreed to.", null: false, visibility: :internal

      field :plan, Objects::Plan, visibility: :internal, null: false,
        description: "The GitHub::Plan for this Organization", method: :async_plan

      def terms_of_service_type
        @object.terms_of_service.async_name
      end

      field :active_enterprise_cloud_trial, Boolean, description: "Whether the organization has an active Enterprise Cloud Trial", method: :has_active_enterprise_cloud_trial?, null: false, visibility: :internal

      field :interaction_ability,
        Objects::RepositoryInteractionAbility,
        description: "The interaction ability settings for this organization.",
        null: true

      def interaction_ability
        @object.async_can_read_interaction_limits?(context[:viewer]).then do |can_read|
          next unless can_read
          Platform::Models::RepositoryInteractionAbility.new(@object)
        end
      end

      field :web_commit_signoff_required, Boolean, null: false, description: "Whether contributors are required to sign off on web-based commits for repositories in this organization."

      def web_commit_signoff_required
        accessible = context[:permission].access_allowed?(
          :view_org_settings,
          resource: @object,
          current_org: @object,
          current_repo: nil,
          allow_integrations: true,
          allow_user_via_granular_actor: true
        )

        if accessible
          @object.async_configuration_owners.then do
            @object.dco_signoff_enabled?
          end
        else
          raise Errors::Forbidden.new(
            "#{context[:viewer].display_login} does not have the right permission to view webCommitSignoffRequired."
          )
        end
      end

      field :ruleset, Objects::RepositoryRuleset,
        minimum_accepted_scopes: ["admin:org"],
        description: "Returns a single ruleset from the current organization by ID.",
        null: true do
          argument :database_id, Integer, "The ID of the ruleset to be returned.", required: true
          argument :include_parents, Boolean, "Include rulesets configured at higher levels that apply to this organization.", required: false, default_value: true
        end

      def ruleset(**arguments)
        @object.async_business.then do
          rulesets = ::RepositoryRuleset.load_for(source: @object, include_parents: arguments[:include_parents])
          # Return rulesets that are
          # 1. created by this source OR inherited enabled rulesets
          # 2. not a member privilege ruleset (branch, tag, push) OR is a member privilege ruleset and member privilege rulesets are enabled with provided feature flag
          #
          # check 2 can be removed when the `member_privilege_rulesets` ff is removed
          ruleset = rulesets
            .filter { |ruleset| (ruleset.enabled? || ruleset.source == @object) && (ruleset.target != "repository" || (@object.member_privilege_rulesets_enabled? && @context[:feature_flags].include?(:member_privilege_rulesets))) }
            .find { |ruleset| ruleset.id == arguments[:database_id] }
          if ruleset
            # track what node the query was from
            # which may be different from the true source of the ruleset if inherited
            ruleset.source_node = @object
          end
          ruleset
        end
      end

      field :rulesets, Platform::Connections::RepositoryRuleset,
        minimum_accepted_scopes: ["admin:org"],
        description: "A list of rulesets for this organization.",
        null: true,
        connection: true do
          argument :include_parents, Boolean, "Return rulesets configured at higher levels that apply to this organization", required: false, default_value: true
          argument :targets, [Enums::RepositoryRulesetTarget], "Return rulesets that apply to the specified target", required: false, default_value: nil
        end

      def rulesets(include_parents: nil, targets:)
        @object.async_business.then do
          # Return rulesets that are
          # 1. created by this source OR inherited enabled rulesets
          # 2. not a member privilege ruleset (branch, tag, push) OR is a member privilege ruleset and member privilege rulesets are enabled with provided feature flag
          #
          # check 2 can be removed when the `member_privilege_rulesets` ff is removed
          rulesets = ::RepositoryRuleset.load_for(source: @object, include_parents:, targets:)
            .filter { |ruleset| (ruleset.enabled? || ruleset.source == @object) && (ruleset.target != "repository" || (@object.member_privilege_rulesets_enabled? && @context[:feature_flags].include?(:member_privilege_rulesets))) }
            .each { |ruleset| ruleset.source_node = @object }
          ArrayWrapper.new(rulesets)
        end
      end

      url_fields prefix: :teams, description: "The HTTP URL listing organization's teams" do |org|
        template = Addressable::Template.new("/orgs/{login}/teams")
        template.expand login: org.display_login
      end

      url_fields prefix: :new_team, description: "The HTTP URL creating a new team" do |org|
        template = Addressable::Template.new("/orgs/{login}/new-team")
        template.expand login: org.display_login
      end

      field :issue_types, Connections.define(Objects::IssueType), "A list of the organization's issue types", connection: true, null: true do
        argument :order_by, Inputs::IssueTypeOrder, description: "Ordering options for issue types returned from the connection.", required: false, default_value: { field: "created_at", direction: "ASC" }
      end

      def issue_types(order_by: nil)
        return unless @object.issue_types_enabled?

        can_list_types = context[:permission].access_allowed?(
          :list_org_issue_types,
          resource: @object,
          current_org: @object,
          current_repo: nil,
          allow_integrations: true,
          allow_user_via_granular_actor: true
        )

        raise Errors::Forbidden.new("#{@context[:viewer]&.display_login || 'user'} does not have permission to retrieve issueType information.") unless can_list_types

        with_async_database_error_fallback(
          @object.async_readable_issue_types_matrix(@context[:viewer]).then do |matrix|
            @object.async_issue_types.then do |issue_types|
              Helpers::IssueTypes.order(issue_types.select { |type| type.readable?(matrix) }, order_by)
            end
          end,
          fallback: -> { raise Platform::Errors::ServiceUnavailable, "Issue types are currently unavailable." }
        )
      end

      field :issue_fields, Connections.define(Platform::Unions::IssueFields), "A list of the organization's issue fields", connection: true, null: true do
        argument :order_by, Inputs::IssueFieldOrder, description: "Ordering options for issue fields returned from the connection.", required: false, default_value: { field: "created_at", direction: "ASC" }
      end

      def issue_fields(order_by: nil)
        return ArrayWrapper.new([]) unless IssueFieldsFeature.enabled?(@object, actor: @context[:viewer])
        with_async_database_error_fallback(
          Platform::Loaders::IssueFields.load(@object).then do |fields|
            next ArrayWrapper.new([]) if fields.empty?
            next ArrayWrapper.new(fields) if order_by.nil?
            issue_fields_order_by(order_by: order_by[:field], direction: order_by[:direction], fields: fields)
          end,
          fallback: -> { raise Platform::Errors::ServiceUnavailable, "Issue fields are currently unavailable." }
        )
      end

      def issue_fields_order_by(order_by:, direction:, fields:)
        unless %w(name created_at).include?(order_by)
          raise Platform::Errors::Validation, "Invalid order_by value: #{order_by}. Must be either 'name' or 'created_at'"
        end
        ArrayWrapper.new(Platform::Helpers::IssueField.sort(fields, order_by, direction))
      end

      field :is_copilot_mobile_chat_enabled, Boolean, required_capabilities: [:mobile_only_schema_mask], description: "Whether Copilot Chat for Mobile is enabled for this organization", null: false

      def is_copilot_mobile_chat_enabled
        Copilot::Organization.new(object).mobile_chat_enabled?
      end

      # TODO: Remove as a part of https://github.com/github/issues/issues/11515 (@Mattamorphic)
      field :excluded_issue_types_repositories, Connections.define(Objects::Repository), "A list of the organization's repositories which are excluded from using the issue types", connection: true, null: true do
        visibility :under_development
        argument :order_by, Inputs::RepositoryOrder, "Ordering options for repositories", required: false, default_value: { field: "name", direction: "ASC" }
      end

      def excluded_issue_types_repositories(order_by:)
        ArrayWrapper.new([])
      end

      field :announcement_banner, Objects::AnnouncementBanner, description: "The announcement banner set on this organization, if any. Only visible to members of the organization's enterprise.", null: true

      def announcement_banner
        EnterpriseBanner.find_by(owner: @object)
      end

      field :has_hosted_runner_custom_images_enabled, Boolean, description: "Whether usage of custom images in hosted Actions runners is enabled.", null: false, visibility: :internal

      def has_hosted_runner_custom_images_enabled
        HostedRunnersHelper::is_custom_images_permitted?(@object)
      end

      private

      def has_octoshift_import_auth?
        context[:permission].access_allowed?(
          :octoshift_import,
          resource: object,
          organization: object,
          current_repo: nil
        )
      end
    end
  end
end
