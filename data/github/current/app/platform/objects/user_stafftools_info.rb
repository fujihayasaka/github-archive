# typed: false
# frozen_string_literal: true

module Platform
  module Objects
    class UserStafftoolsInfo < Platform::Objects::Base

      LAST_FIVE_ISSUE_COMMENTS_BATCH_SIZE = 100

      description "User information only visible to site admin"

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

      visibility :internal

      minimum_accepted_scopes ["site_admin"]

      implements Interfaces::AccountStafftoolsInfo

      field :associated_record_creation_velocity, Integer, description: "Records created per hour while active.", null: false do
        argument :type, Enums::UserAssociatedRecordType, "The associated record type", required: true
      end

      def associated_record_creation_velocity(**arguments)
        Loaders::AssociatedRecordCreationVelocity.load(@object.account, arguments[:type])
      end

      field :associated_record_first_created_at, Scalars::DateTime, description: "First created at time for record type.", null: true do
        argument :type, Enums::UserAssociatedRecordType, "The associated record type", required: true
      end

      def associated_record_first_created_at(**arguments)
        Loaders::AssociatedRecordFirstCreatedAt.load(@object.account, arguments[:type])
      end

      field :has_gpg_key, Boolean, description: "The account has at least one gpg key.", null: false

      def has_gpg_key
        account = @object.account

        Loaders::AssociatedRecordsExist.load(account, :gpg_keys)
      end

      field :has_ssh_key, Boolean, description: "The account has at least one ssh key.", null: false

      def has_ssh_key
        account = @object.account

        Loaders::AssociatedRecordsExist.load(account, :public_keys)
      end

      field :has_used_anonymizing_proxy, Boolean, description: "Whether the account has used an anonymized proxy to access GitHub.", null: false

      def has_used_anonymizing_proxy
        account = @object.account

        account.anonymizing_proxy_user?
      end

      field :primary_email, String, description: "The primary email address of the user.", null: true

      def primary_email
        @object.account.async_primary_user_email.then do
          @object.account.email
        end
      end

      field :primary_email_domain_reputation, Objects::SpamuraiReputation, description: "Primary email domain reputation.", null: false

      def primary_email_domain_reputation
        @object.account.async_primary_user_email.then do
          EmailDomainReputationRecord.reputation(@object.account.email)
        end
      end

      field :primary_email_domain_metadata, Objects::EmailDomainMetadata, description: "Primary email domain metadata.", null: false

      def primary_email_domain_metadata
        @object.account.async_primary_user_email.then do
          EmailDomainReputationRecord.metadata(@object.account.email)
        end
      end

      field :wiki_edit_count, Integer, description: "The number of times this user has edited a wiki.", null: false

      def wiki_edit_count
        GitHub::SpamChecker.wiki_edits(@object.account).size
      end

      field :oauth_applications, Connections.define(Objects::OauthApplication), description: "Authorized Oauth applications.", null: false, connection: true

      def oauth_applications
        @object.account.oauth_applications.scoped
      end

      field :oauth_accesses, Connections.define(Objects::OauthAccess), description: "OAuth accesses.", null: false, connection: true

      def oauth_accesses
        @object.account.oauth_accesses.scoped
      end

      field :accounts_sharing_deobfuscated_email, resolver: Resolvers::AccountsSharingDeobfuscatedEmail, connection: true do
        description "Accounts that share a deobfuscated email with this one."
      end

      field :obfuscated_duplicate_emails, description: "Obfuscated duplicate user emails.", resolver: Resolvers::ObfuscatedDuplicateEmails, connection: true


      field :organization, Objects::Organization, description: "Find an organization by its login that the user belongs to.", null: true do
        argument :login, String, "The login of the organization to find.", required: true
      end

      def organization(**arguments)
        scope = @object.account.organizations
        scope.find_by_login(arguments[:login])
      end

      field :organizations, Connections.define(Objects::Organization), null: false, connection: true, description: "Organization the user belongs to." do
        argument :order_by, Inputs::OrganizationOrder, "Ordering options for organizations returned from the connection.", required: false,
          default_value: { field: "created_at", direction: "DESC" }
      end

      def organizations(**args)
        org_memberships = @object.account.organizations

        if args[:order_by]
          field = args[:order_by][:field]
          direction = args[:order_by][:direction]
          org_memberships = org_memberships.reorder("users.#{field} #{direction}")
        end
      end

      field :owned_organizations, Connections.define(Objects::Organization), null: false, connection: true, description: "Organization the user owns." do
        argument :order_by, Inputs::OrganizationOrder, "Ordering options for organizations returned from the connection.", required: false,
          default_value: { field: "created_at", direction: "DESC" }
      end

      def owned_organizations(**args)
        owned_orgs = @object.account.owned_organizations

        if args[:order_by]
          field = args[:order_by][:field]
          direction = args[:order_by][:direction]
          owned_orgs = owned_orgs.reorder("users.#{field} #{direction}")
        end
      end

      field :user_sessions, Connections.define(Objects::UserSession), visibility: :internal, description: "User sessions.", null: false, connection: true

      def user_sessions
        @object.account.sessions
      end

      field :authentication_records, Connections.define(Objects::AuthenticationRecord), "A list of successful logins for a user.", null: false, connection: true

      def authentication_records
        @object.account.authentication_records
      end

      field :user_emails, Connections.define(Objects::UserEmail), "A list of user emails for a user.", null: false, connection: true

      def user_emails
        @object.account.emails
      end

      field :has_two_factor_authentication_enabled, Boolean, visibility: :internal, description: "Indicates if the user has enabled two factor authentication.", null: true

      def has_two_factor_authentication_enabled
        @object.account.async_two_factor_credential.then do
          @object.account.two_factor_authentication_enabled?
        end
      end

      field :received_abuse_reports, Connections.define(Objects::AbuseReport), description: "The abuse reports received for this user.", connection: true, null: false do
        argument :order_by, Inputs::AbuseReportOrder, "Ordering options for abuse reports returned from the connection.", required: false,
          default_value: { field: "created_at", direction: "DESC" }
      end

      def received_abuse_reports(order_by:)
        scope = @object.account.received_abuse_reports
        table = scope.table_name

        scope = scope.order("#{table}.#{order_by[:field]} #{order_by[:direction]}")
        scope
      end

      field :blocked_by_count, Integer, description: "The number of users that have blocked this account.", null: false

      def blocked_by_count
        @object.account.ignored_by_users.count
      end

      field :following, Connections::Following, description: "A list of users the given user is following. Includes spammy users.", null: false, connection: true do
        argument :user_database_ids, [Integer, null: true], "Optional list of user IDs to filter results. If provided, only following users in this list will be returned",
          visibility: :internal, required: false
        argument :order_by, Inputs::FollowOrder, "How to order the followed users. Defaults to most recently followed users first.", required: false,
          visibility: :internal, default_value: { field: "followed_at", direction: "DESC" }
      end

      def following(user_database_ids: nil, order_by: nil)
        followings = @object.account.followings
        followings = followings.where(following_id: user_database_ids) if user_database_ids
        followings = followings.order(created_at: order_by[:direction]) if order_by[:field] == "followed_at"
        followings
      end

      field :followers, Connections::Follower, description: "A list of users the given user is followed by. Includes spammy users.", null: false, connection: true do
        argument :order_by, Inputs::FollowOrder, "How to order the followers. Defaults to most recent followers first.", required: false,
          visibility: :internal, default_value: { field: "followed_at", direction: "DESC" }
      end

      def followers(order_by: nil)
        followers = @object.account.followeds
        followers = followers.order(created_at: order_by[:direction]) if order_by[:field] == "followed_at"

        followers
      end

      field :accounts_cluster, [Unions::Account], description: "Find accounts in same signup time cluster as account by ip address.", null: true

      def accounts_cluster(**arguments)
        ::Spam.find_cluster_for(@object.account)
      end

      def public_issues_search_results(user, viewer)
        # consider sort:updated-desc
        search_params = "is:issue is:public sort:updated-desc author:#{user.login}"
        search_query = ::Search::Queries::IssueQuery.parse(search_params, viewer)
        ::Issue::SearchResult.search(
          query: search_query,
          prefill_associations: false,
          per_page: 5,
          show_spam_to_staff: true,
          current_user: viewer,
          context: "#{self.class.name&.demodulize.underscore}-#{__method__}",
        )
      end

      field :last_five_public_issues, [Issue], description: "The five most recently created issues from the user", null: true

      def last_five_public_issues(**arguments)
        if @object.account.spammy?
          begin
            public_issues(@object.account).without_pull_requests.order("updated_at asc").limit_execution_time(limit_ms: 2000).last(5)
          rescue ActiveRecord::StatementTimeout
            []
          end
        else
          result = public_issues_search_results(@object.account, @context[:viewer])
          result[:issues]
        end
      end

      field :public_issues_total_count, Integer, description: "Count of public issues opened", null: false

      def public_issues_total_count(**arguments)
        if @object.account.spammy?
          begin
            public_issues(@object.account).without_pull_requests.limit_execution_time(limit_ms: 2000).count
          rescue ActiveRecord::StatementTimeout
            -1
          end
        else
          result = public_issues_search_results(@object.account, @context[:viewer])
          result[:open_count] + result[:closed_count]
        end
      end

      def public_issues(account)
        repo_ids = account.issues.select(:repository_id).distinct.pluck(:repository_id)
        public_repo_ids = ::Repository.public_scope.active.where(id: repo_ids).pluck(:id)
        account.issues.where(repository_id: public_repo_ids)
      end

      field :last_five_public_issue_comments, [IssueComment], description: "The five most recently created issue comments from the user", null: true

      def last_five_public_issue_comments(**arguments)
        comments_to_return = []

        offset = 0
        base_relation = @object.account.issue_comments
          .from("`issue_comments` IGNORE INDEX FOR ORDER BY (PRIMARY)")
          .joins(:issue)
          .merge(::IssueComment.order(created_at: :desc))
          .limit(LAST_FIVE_ISSUE_COMMENTS_BATCH_SIZE)

        while comments_to_return.size != 5
          comments = base_relation.offset(offset).to_a
          break if comments.empty?

          public_repo_ids = ::Repository.public_scope.active.where(id: comments.map(&:repository_id)).pluck(:id)
          public_comments = comments.select { |comment| public_repo_ids.include?(comment.repository_id) }
          comments_to_return = (comments_to_return + public_comments).first(5)
          break if comments_to_return.size == 5
          offset += LAST_FIVE_ISSUE_COMMENTS_BATCH_SIZE
        end

        comments_to_return
      end

      field :codeql_databases, Connections::CodeqlDatabase, description: "A list of CodeQL databases uploaded by this user", null: true, visibility: :internal, connection: true do
        argument :order_by, Inputs::CodeqlDatabaseOrder, "Ordering options for CodeQL databases returned.", required: false, default_value: { field: "created_at", direction: "DESC" }
      end
      def codeql_databases(order_by:)
        unless self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          return nil
        end

        query = ::CodeqlDatabase.where(uploader_id: @object.account.id)
        if order_by[:field] == "created_at"
          query = query.order(created_at: order_by[:direction])
        elsif order_by[:field] == "size"
          query = query.order(size: order_by[:direction])
        end
        query
      end

      field :copilot_usage, Objects::UserCopilotUsage, description: "Copilot usage for this user", null: true, visibility: :internal
      def copilot_usage
        Copilot::AggregateUsageDetail.latest_for_users(@object.account)
      end

      field :models_usage, Integer, description: "Count of GitHub Models auth requests for this user", null: true, visibility: :internal
      def models_usage
        GitHubModels::UsageDetails.auths_count_for_user_id(@object.account.id)
      end

      field :has_recently_updated_content_on_any_tables, Boolean, description: "Has the user recently created content on any of these tables?", null: false do
        argument :tables, [Enums::AccountSpammableTable], "An array of spammable tables that belong to accounts", required: true
        argument :since, Integer, "Seconds since the user has created content, defaults to 24 hours ago in seconds", required: false
      end
      def has_recently_updated_content_on_any_tables(tables:, since: 24.hours)
        Spam::UserGeneratedContent.has_recently_updated_content_on_any_table?(tables, @object.account.id, since: since.seconds)
      end
    end
  end
end
