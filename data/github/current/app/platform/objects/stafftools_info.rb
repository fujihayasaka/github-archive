# typed: false
# frozen_string_literal: true

module Platform
  module Objects
    class StafftoolsInfo < Platform::Objects::Base
      description "Stafftools information for site admins."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
      end

      # TODO before going public, fix `camelize: false` arguments below to be camelized
      visibility :internal

      minimum_accepted_scopes ["site_admin"]

      field :accounts, Connections.define(Unions::Account), description: "Lookup user, organization, and bot accounts, oldest to newest.", null: true, connection: true

      def accounts
        ::User.oldest_to_newest
      end

      field :accounts_for_logins, [Unions::Account], description: "Lookup user, organization, and bot accounts by login.", null: true do
        argument :logins, [String], "The logins of the users, organizations, or bots. Limit 100.", required: true
      end

      def accounts_for_logins(logins:)
        raise Errors::Validation, "Only up to 100 logins is supported." if logins.size > 100

        ::User.with_logins(logins).limit(100)
      end

      field :accounts_from_last_ip, Connections.define(Unions::Account), description: "Lookup user, organization, and bot accounts from last IP.", null: true, connection: true do
        argument :ip, String, "IPv4 network address.", required: true
        argument :prefix, Enums::NetworkPrefix, Enums::NetworkPrefix.description, default_value: 32, required: false
      end

      def accounts_from_last_ip(**arguments)
        ::User.by_ip_with_prefix(arguments[:ip], prefix: arguments[:prefix])
      end

      field :ip_neighbors_count, Integer, description: "The count users for an IP neighborhood.", null: false do
        argument :ip, String, "IPv4 network address.", required: true
        argument :prefix, Enums::NetworkPrefix, Enums::NetworkPrefix.description, default_value: 32, required: false
      end

      def ip_neighbors_count(ip:, prefix:)
        ::User.by_ip_with_prefix(ip, prefix: prefix).count
      end

      field :spammy_ip_neighbors_count, Integer, description: "The count of spammy users for an IP neighborhood.", null: false do
        argument :ip, String, "IPv4 network address.", required: true
        argument :prefix, Enums::NetworkPrefix, Enums::NetworkPrefix.description, default_value: 32, required: false
      end

      def spammy_ip_neighbors_count(ip:, prefix:)
        ::User.spammy.by_ip_with_prefix(ip, prefix: prefix).count
      end

      field :enterprises, Connections.define(Objects::Enterprise), visibility: :internal, description: "Fetch all enterprise accounts.", null: false, connection: true

      def enterprises
        ::Business.by_slug
      end

      field :account_from_database_id, Unions::Account, description: "Account from database id.", null: true do
        argument :database_id, Integer, "Account database id.", required: true
        argument :enterprise, Boolean, required: false, default_value: false, description: "Whether to search for an Enterprise or not."
      end

      def account_from_database_id(database_id:, enterprise: false)
        account_class = enterprise ? ::Business : ::User
        Loaders::ActiveRecord.load(account_class, database_id)
      end

      field :account_from_analytics_tracking_id, Unions::Account, description: "Account from analytics tracking id.", null: true do
        argument :analytics_tracking_id, String, "Account analytics tracking id.", required: true
      end

      def account_from_analytics_tracking_id(analytics_tracking_id:)
        ::User.find_by(analytics_tracking_id: analytics_tracking_id)
      end

      field :early_access_memberships, Connections.define(Objects::EarlyAccessMembership), visibility: :internal, description: "Submitted user requests to join early access programs", connection: true, null: true do
        argument :feature, Enums::EarlyAccessMembershipFeature,
          description: "The early access feature to get memberships for.",
          required: true
        argument :filter, Enums::EarlyAccessMembershipFilter,
          description: "The condition to filter memberships by.",
          required: false,
          default_value: :all
        argument :query, String,
          description: "The login of a user to search for a membership for.",
          required: false
        argument :order_by, Inputs::EarlyAccessMembershipOrder,
          description: "Ordering options for memberships returned from the connection.",
          required: false,
          default_value: { field: "created_at", direction: "ASC" }
      end

      def early_access_memberships(**arguments)
        scope = ::EarlyAccessMembership.where(feature_slug: arguments[:feature])

        case arguments[:filter]
        when :pending
          scope = scope.where(feature_enabled: false)
        when :accepted
          scope = scope.where(feature_enabled: true)
        end

        if arguments[:query]
          query = ActiveRecord::Base.sanitize_sql_like(arguments[:query].strip)

          # Get the ids for the matching members of eligible types
          business_ids = ::Business.where(["slug LIKE :query", { query: "%#{query}%" }]).pluck(:id)
          user_ids = ::User.where(["login LIKE :query", { query: "%#{query}%" }]).pluck(:id)

          scope = scope.where(
            member_type: "Business", member_id: business_ids,
          ).or(
            scope.where(
              member_type: "User", member_id: user_ids,
            ),
          )
        end

        order_by = arguments[:order_by]
        scope.order(order_by[:field] => order_by[:direction])
      end

      field :email_domain_reputation, Objects::SpamuraiReputation, visibility: :internal, description: "Reputation data for an email domain.", null: false do
        argument :address, String, description: "Email address or domain name.", required: true
        argument :address_type, Enums::EmailDomainAddressType, description: "Lookup address type.", default_value: :email_domain, required: false
      end

      def email_domain_reputation(**arguments)
        EmailDomainReputationRecord.reputation(arguments[:address], address_type: arguments[:address_type])
      end

      field :email_domain_metadata, Objects::EmailDomainMetadata, visibility: :internal, description: "Metadata for an email domain.", null: false do
        argument :address, String, description: "Email address or domain name.", required: true
        argument :address_type, Enums::EmailDomainAddressType, description: "Lookup address type.", default_value: :email_domain, required: false
      end

      def email_domain_metadata(**arguments)
        EmailDomainReputationRecord.metadata(arguments[:address], address_type: arguments[:address_type])
      end

      field :accounts_for_email_domain, Connections.define(Unions::Account), description: "Lookup user accounts by email domain.", null: true, connection: true do
        argument :address, String, description: "Email address or domain name.", required: true
        argument :include_spammy, Boolean, description: "Include spammy accounts.", required: false, default_value: false
        argument :emails_added_since, Platform::Scalars::DateTime, description: "Only include accounts with emails added since this date and time.", required: false
      end

      def accounts_for_email_domain(**arguments)
        email_domain = EmailDomainReputationRecord.normalize_domain(arguments[:address])

        scope = ::UserEmail.from("user_emails FORCE INDEX (index_user_emails_on_normalized_domain_and_user_id)").where("normalized_domain = ?", email_domain).distinct.order("user_id DESC")

        unless arguments[:include_spammy]
          scope = scope.joins(:user).not_spammy
        end

        user_ids = scope.limit(10000).pluck(:user_id).reverse

        ::User.where(id: user_ids)
      end

      field :accounts_for_email_pattern, Connections.define(Unions::Account), description: "Lookup user accounts by email pattern.", null: true, connection: true do
        argument :pattern, String, description: "Email pattern.", required: true
        argument :days, Integer, description: "Number of days to look back.", required: false, default_value: 3
        argument :include_spammy, Boolean, description: "Include spammy accounts.", required: false, default_value: false
      end

      def accounts_for_email_pattern(**arguments)
        scope = ::UserEmail.order("user_id ASC")
        scope = scope.where("user_emails.email LIKE ?", arguments[:pattern])
        scope = scope.where("user_emails.created_at > ?", arguments[:days].days.ago)
        scope = scope.distinct

        unless arguments[:include_spammy]
          scope = scope.joins(:user).not_spammy
        end

        user_ids = scope.pluck(:user_id)
        ::User.where(id: user_ids)
      end

      field :accounts_for_emails, [Unions::Account], description: "Lookup user for email addresses.", null: true do
        argument :addresses, [String], "User email addresses. Limit 100.", required: true
      end

      def accounts_for_emails(**arguments)
        raise Errors::Validation, "Only up to 100 emails is supported." if arguments[:addresses].size > 100

        scope = ::UserEmail.joins(:user).where("email IN (?)", arguments[:addresses]).distinct.limit(100).order("user_id ASC")
        user_ids = scope.pluck(:user_id)
        ::User.where(id: user_ids)
      end

      field :user_asset_urls, [Objects::UserAssetUrl], description: "Look up the urls for user assets.", null: true do
        argument :ids, [Int], "User Asset Database IDs. Limit 100.", required: true
      end

      def user_asset_urls(**arguments)
        raise Errors::Validation, "Only up to 100 assets is supported." if arguments[:ids].size > 100
        ::UserAsset.where(id: arguments[:ids]).order(id: :asc).map do |asset|
          { id: asset.id, url: asset.redirect_url(expiration: 24.hours.seconds) }
        end
      end

      field :user_attachment_urls, Connections.define(Unions::UserAttachmentUrls), description: "Look up the urls for user attachments.", null: true do
        argument :ids, [Int], "User Attachment Database IDs. Limit 100.", required: true
        argument :type, Enums::UserAttachmentUrlsType, "Filter by attachment type", required: true
        argument :order_by,
          Inputs::UserAttachmentUrlsOrder,
          "Ordering options for user attachment urls returned from the connection",
          required: false,
          default_value: { field: "created_at", direction: "DESC" }
      end

      def user_attachment_urls(**arguments)
        raise Errors::Validation, "Only up to 100 attachments are supported." if arguments[:ids].size > 100
        case arguments[:type]
        when :copilot_chat_attachment
          ::Copilot::ChatAttachment.where(id: arguments[:ids]).order(id: :asc)
        when :github_runtime_deployment
          ::Spark::RuntimeAppDeploy.where(id: arguments[:ids]).order(id: :asc)
        end
      end

      field :user_attachments, Connections.define(Unions::UserAttachment), description: "Look up the attachments uploaded by a user.", null: true do
        argument :user_id, Int, "User ID", required: true
        argument :type, Enums::UserAttachmentType, "Filter by attachment type", required: true
        argument :order_by,
          Inputs::UserAttachmentsOrder,
          "Ordering options for user attachments returned from the connection",
          required: false,
          default_value: { field: "created_at", direction: "DESC" }
      end

      def user_attachments(type:, user_id:, order_by:)
        scope = case type
        when :non_media
          ::RepositoryFile.where(uploader_id: user_id)
        when :media
          ::UserAsset.where(user_id: user_id)
        when :copilot_chat_attachment
          ::Copilot::ChatAttachment.where(uploader_id: user_id)
        end

        scope.order(order_by[:field] => order_by[:direction])
      end

      field :audit_log_json, resolver: Resolvers::AuditLogJson, connection: true do
        description "Audit log entries matching the given query."
      end

      field :audit_log_actions, [String], null: false,
        description: "List of all possible non-deprecated audit log entry actions."

      def audit_log_actions
        Audit::ACTIONS
      end

      field :deprecated_audit_log_actions, [String], null: false,
        description: "List of all possible deprecated audit log entry actions."

      def deprecated_audit_log_actions
        Audit::DEPRECATED_ACTIONS
      end

      field :retired_namespaces,
        Connections.define(Objects::RetiredNamespace),
        description: "List retired namespaces for a specified owner login.",
        connection: true,
        null: true do
        argument :login,
          String,
          description: "The owner login to return retired namespaces for.",
          required: true
        argument :order_by,
          Inputs::RetiredNamespaceOrder,
          "Ordering options for namespaces returned from the connection",
          required: false,
          default_value: { field: "created_at", direction: "ASC" }
      end

      def retired_namespaces(**arguments)
        scope = ::RetiredNamespace.unscoped.where(owner_login: arguments[:login])
        order_by = arguments[:order_by]
        scope.order(order_by[:field] => order_by[:direction])
      end

      field :reused_card_fingerprints, [Objects::ReusedCardFingerprint], description: "List of reused card fingerprints in the last 30 days.", null: false

      def reused_card_fingerprints(**arguments)
        ::PaymentMethod.with_card_fingerprint_reuse_over_threshold_in_last_30_days
      end

      field :resolve_url_to_type, resolver: Resolvers::ResolveUrlToType, description: "Resolve a URL to a GraphQL type."

      field :resolve_id_to_url, resolver: Resolvers::ResolveIdToUrl, description: "Resolve a Global Relay ID to a URL."

      field :pages_repository_from_cname, Objects::Repository, description: "Find a repository by its Pages custom domain.", null: true do
        argument :cname, String, "The custom domain (cname) of the pages site", required: true
      end

      def pages_repository_from_cname(cname:)
        page = Page.find_by(cname: cname)
        page&.repository
      end
    end
  end
end
