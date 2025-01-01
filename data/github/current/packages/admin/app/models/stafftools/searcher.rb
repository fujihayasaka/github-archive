# typed: true
# frozen_string_literal: true

module Stafftools
  class Searcher
    attr_reader :query, :results

    GPG_KEY_PATTERN = /\A[A-F0-9]{16}\z/i
    StafftoolsSearchResults = Struct.new(
      :users, :businesses, :deleted_businesses, :customers, :repositories, :gists,
      :oauth_app_user_counts, :oauth_apps, :integrations,
      :integration_installations, :fuzzy_users, :deleted_users, :renamed_user, :teams,
      :old_name, :gpg_keys, :gpg_key_users, :public_key, :oauth_access, :oauth_application, :integration, :hook, :audit_log_query_phrases) do
        def initialize(*)
          super
          self.users ||= []
          self.businesses ||= []
          self.deleted_businesses ||= []
          self.customers ||= []
          self.repositories ||= []
          self.gists ||= []
          self.oauth_app_user_counts ||= {}
          self.oauth_apps ||= []
          self.integrations ||= []
          self.integration_installations ||= []
          self.fuzzy_users ||= []
          self.deleted_users ||= []
          self.teams ||= []
          self.audit_log_query_phrases ||= {}
        end
      end

    def initialize(query, current_user)
      @results = StafftoolsSearchResults.new
      @query = (query || "").strip
      @current_user = current_user
    end

    def search_for_gpg_key
      if @query =~ GPG_KEY_PATTERN
        GitHub.tracer.in_span("stafftools.searcher.search_for_gpg_key", kind:  :internal) do
          key_id = [@query.downcase].pack("H*")
          @results.gpg_keys = ::GpgKey.where(key_id: key_id)

          @results.gpg_key_users = @results.gpg_keys.map { |k| k.user }
        end
      end
      self
    end

    def search_for_users
      GitHub.tracer.in_span("stafftools.searcher.search_for_users", kind: :internal) do
        search_for_gpg_key if @results.gpg_key_users.nil?
        standard_user_search
        coupon_users_search
        spammy_users_search
        deleted_users_search if search_audit_logs?
        ignore_soft_deleted_organizations
        sdn_screening_id_users_search
      end
      @results.users.uniq!
      @results.users.compact!
      self
    end

    def search_for_businesses
      GitHub.tracer.in_span("stafftools.searcher.search_for_businesses", kind: :internal) do
        businesses_search
        fuzzy_businesses_search
        deleted_businesses_search
        sdn_screening_id_businesses_search
      end
      @results.businesses.uniq!
      @results.businesses.compact!
      self
    end

    def search_for_customers
      customers_search
      @results.customers.uniq!
      @results.customers.compact!
      self
    end

    def search_for_teams
      GitHub.tracer.in_span("stafftools.searcher.search_for_teams", kind: :internal) do
        @results.teams << ::Team.find_by(id: @query) if numeric_query?
        if @query.count("/") == 1
          org, team = @query.split("/")
          @results.teams += ::Team.joins(:organization).where(users: { login: org }).where(slug: team)
        end
      end
      @results.teams.uniq!
      @results.teams.compact!
      self
    end

    def search_for_renamed_users
      # We can't query for "action:user.rename" because it's indexed with the
      # new name only.
      GitHub.tracer.in_span("stafftools.searcher.search_for_renamed_users", kind: :internal) do
        phrase = "(user:#{@query} OR org:#{@query})"
        if GitHub.driftwood_ade_queries_enabled?
          phrase = "webevents | where user == '#{@query}' or org == '#{@query}'"
        end

        results = GitHub.tracer.in_span("stafftools.searcher.search_for_renamed_users.driftwood") do
          es_query = Audit::Driftwood::Query.new_stafftools_query(
            phrase: phrase,
            current_user: @current_user,
          )
          es_query.execute
        end
        GitHub.tracer.in_span("stafftools.searcher.search_for_renamed_users.audit_logs", kind: :internal) do
          logs = ::AuditLogEntry.new_from_array(results)
          if (log = logs.find { |l| l.hit[:org]&.downcase == @query.downcase || l.hit[:user]&.downcase == @query.downcase })
            id = log.hit[:org] == @query ? log.org_id : log.user_id
            @results.renamed_user = ::User.find_by(id: id)
            @results.old_name = @query
          end
        end
      end
      self
    end

    def search_for_repositories
      GitHub.tracer.in_span("stafftools.searcher.search_for_repositories", kind: :internal) do
        fuzzy_repository_search
        repos_search
      end
      @results.repositories.uniq!
      @results.repositories.compact!
      self
    end

    def search_for_azure_subscription
      azure_subscription_search
      @results.customers.uniq!
      @results.customers.compact!
      @results.businesses.uniq!
      @results.businesses.compact!
      @results.users.uniq!
      @results.users.compact!
      self
    end

    def search_for_gists
      GitHub.tracer.in_span("stafftools.searcher.search_for_gists", kind: :internal) do
        @results.gists << ::Gist.with_name_with_owner(@query, nil, true)
        @results.gists << ::Gist.find_by(repo_name: @query)
      end
      @results.gists.uniq!
      @results.gists.compact!
      self
    end

    def search_for_oauth_application
      GitHub.tracer.in_span("stafftools.searcher.search_for_oauth_application", kind: :internal) do
        apps = []
        if numeric_query?
          apps << ::OauthApplication.find_by(id: @query)
        end
        apps << ::OauthApplication.find_by(name: @query)
        apps = apps.compact.uniq
        unless apps.empty?
          sql = Arel.sql(<<-SQL, app_ids: apps.map(&:id))
            SELECT application_id, COUNT(oauth_authorizations.id) AS authorization_count
            FROM     oauth_authorizations
            WHERE    application_id
            IN       (:app_ids)
            GROUP BY application_id
            ORDER BY authorization_count DESC
            LIMIT    50
          SQL
          results = OauthAuthorization.connection.select_rows(sql)
          @results.oauth_app_user_counts = Hash[*results.flatten]
          @results.oauth_apps.concat(apps)
        end
      end
      self
    end

    def search_for_integrations
      GitHub.tracer.in_span("stafftools.searcher.search_for_integrations", kind: :internal) do
        integrations_search
        integration_installations_search if numeric_query?
      end
      @results.integration_installations.uniq!
      @results.integrations.uniq!
      @results.integration_installations.compact!
      @results.integrations.compact!
      self
    end

    # Only handling a few key cases here, that are commonly logged in the GitHub Actions toolchain
    def search_by_global_relay_id
      GitHub.tracer.in_span("stafftools.searcher.search_by_global_relay_id", kind: :internal) do
        begin
          type, id = ::Platform::Helpers::NodeIdentification.from_global_id(@query)
          case type
          when "App"
            integration = ::Integration.find_by(id: id)
            @results.integrations << integration if integration
          when "Enterprise"
            return if GitHub.single_business_environment?

            business = ::Business.find_by(id: id)
            @results.businesses << business if business
          when "Organization", "User"
            user = ::User.find_by(id: id)
            @results.users << user if user
          when "Repository"
            repository = ::Repositories::Public.find_active(id)
            @results.repositories << repository if repository
          when "Team"
            team = ::Team.find_by(id: id)
            @results.teams << team if team
          end
        rescue ::Platform::Errors::NotFound
        end
      end
      self
    end

    def search_for_hook
      GitHub.tracer.in_span("stafftools.searcher.search_for_hook", kind: :internal) do
        @results.hook = Hook.find_by(id: @query) if numeric_query?
      end
      self
    end

    def search_for_public_key
      GitHub.tracer.in_span("stafftools.searcher.search_for_public_key", kind: :internal) do
        @results.public_key = ::PublicKey.find_by(fingerprint_sha256: @query.delete_prefix("SHA256:"))
      end
      self
    end

    def search_for_oauth_access_token
      return self unless OauthAccessTokens::Domain.matches_pattern?(@query)
      GitHub.tracer.in_span("stafftools.searcher.search_for_oauth_access_token", kind: :internal) do
        hashed_token = OauthAccessTokens::Domain.hash_token(@query)
        found_access = OauthAccessTokens.domain.by_hash(hashed_token)
        @results.oauth_access = OauthAccessTokens.domain.by_hash(hashed_token)
      end
      self
    end

    def search_for_oauth_application_by_key
      return self unless OauthAccessTokens::Domain.client_id?(@query)
      GitHub.tracer.in_span("stafftools.searcher.search_for_oauth_application_by_key", kind: :internal) do
        @results.oauth_application = ::OauthApplication.where(key: @query).first
      end
      self
    end

    def search_for_integration_by_key
      return self unless Integration.client_id?(@query)
      GitHub.tracer.in_span("stafftools.searcher.search_for_integration_by_key", kind: :internal) do
        @results.integration = ::Integration.find_by(key: @query)
      end
      self
    end

    def search_audit_logs!
      GitHub.tracer.in_span("stafftools.searcher.search_audit_logs", kind: :internal) do
        deleted_users_search
        if @results.deleted_users.empty?
          search_for_renamed_users
        end
      end
      self
    end

    def search_audit_logs?
      !FeatureFlag.vexi.enabled?(
        "disable_stafftools_search_audit_log_queries", @current_user, default: false
      )
    end

    private

    def user_search_scope
      ::User.without_soft_deleted_organizations
    end

    def standard_user_search
      GitHub.tracer.in_span("stafftools.searcher.standard_user_search", kind: :internal) do
        @results.users = if @query =~ /@/
          GitHub.tracer.in_span("stafftools.searcher.standard_user_search.login_search", kind: :internal) do
            u = T.let([], T.untyped)
            GitHub.tracer.in_span("stafftools.searcher.standard_user_search.email_search", kind: :internal) do
              u << ::User.find_by_email(@query)
            end
            GitHub.tracer.in_span("stafftools.searcher.standard_user_search.profile_email_search", kind: :internal) do
              u += ::User.all_with_profile_email(@query)
            end
            GitHub.tracer.in_span("stafftools.searcher.standard_user_search.gravatar_email_search", kind: :internal) do
              u += user_search_scope.where(gravatar_email: @query).where.not(type: :mannequin).to_a
            end
            GitHub.tracer.in_span("stafftools.searcher.standard_user_search.organization_billing_email_search", kind: :internal) do
              u += user_search_scope.where(organization_billing_email: @query).to_a
            end
            GitHub.tracer.in_span("stafftools.searcher.standard_user_search.external_email_search", kind: :internal) do
              external_emails = ::BillingExternalEmail.where(email: @query, owner_type: "User")
              external_emails.each { |external_email| u += ::User.where(id: external_email.owner_id).to_a }
            end
            u
          end
        elsif GitHub.multi_tenant_enterprise?
          GitHub.tracer.in_span("stafftools.searcher.standard_user_search.multi_tenant_search", kind: :internal) do
            if contains_tenant_suffix?(@query)
              u = T.let(::User.where(login: @query).to_a, T::Array[T.nilable(::User)])
            else
              u = T.let(::User.where(display_login: @query).to_a, T::Array[T.nilable(::User)])
            end

            u << ::User.find_by(id: @query) if numeric_query?

            key_users = @results.gpg_key_users
            u += key_users if key_users
            u
          end
        else
          GitHub.tracer.in_span("stafftools.searcher.standard_user_search.user_id_search", kind: :internal) do
            u = T.let(user_search_scope.where(login: @query).to_a, T::Array[T.nilable(::User)])
            u << ::User.find_by(id: @query) if numeric_query?

            key_users = @results.gpg_key_users
            u += key_users if key_users
            u
          end
        end
      end
    end

    # Returns true if the query contains a tenant suffix.
    def contains_tenant_suffix?(query)
      # Check if the query contains a either a tenant suffix or part of a tenant suffix indicated by the presence of an underscore.
      return true if query.include?("_")

      false
    end

    def coupon_users_search
      GitHub.tracer.in_span("stafftools.searcher.coupon_users_search", kind: :internal) do
        coupon = ::Coupon.find_by_code(@query)
        @results.users += coupon.users if coupon
      end
    end

    # spammy users are _not_ in the search index, so we are doing a fuzzy
    # search in addition to the normal user searches above
    def spammy_users_search
      GitHub.tracer.in_span("stafftools.searcher.spammy_users_search", kind: :internal) do
        fuzzy_finder = ::Search::Queries::UserFuzzyFinder.new current_user: @current_user,
                                                            query: @query, highlight: true
        fuzzyresults = fuzzy_finder.execute
        @results.fuzzy_users = fuzzyresults.results
        @results.fuzzy_users.delete_if do |hit|
          if soft_deleted_organization?(hit["_model"])
            true
          elsif hit["_exact"]
            @results.users << hit["_model"]
            true
          end
        end
      end
    end

    def deleted_users_search
      # Find deleted users
      GitHub.tracer.in_span("stafftools.searcher.deleted_users_search", kind: :internal) do
        user_or_org_delete = "(action:user.delete OR action:org.delete OR action:org.soft_delete OR action:org.async_delete OR action:org.destroy)"
        phrase = if numeric_query?
          "(user:#{@query} OR org:#{@query} OR user_id:#{@query} OR org_id:#{@query}) AND #{user_or_org_delete}"
        elsif @query =~ /@/
          "(data.email:#{@query}) AND #{user_or_org_delete}"
        else
          "(user:#{@query} OR org:#{@query}) AND #{user_or_org_delete}"
        end

        if GitHub.driftwood_ade_queries_enabled?
          phrase = if numeric_query?
            <<~KQL
              webevents
              | where user =~ "#{@query}" or org =~ "#{@query}" or user_id == "#{@query}" or org_id == "#{@query}"
              | where action in ("user.delete", "org.delete", "org.soft_delete", "org.async_delete", "org.destroy")
            KQL
          elsif @query =~ /@/
            <<~KQL
              webevents
              | where data.email =~ "#{@query}"
              | where action in ("user.delete", "org.delete", "org.soft_delete", "org.async_delete", "org.destroy")
            KQL
          else
            <<~KQL
              webevents
              | where user =~ "#{@query}" or org =~ "#{@query}"
              | where action in ("user.delete", "org.delete", "org.soft_delete", "org.async_delete", "org.destroy")
            KQL
          end
        end

        results = GitHub.tracer.in_span("stafftools.searcher.deleted_users_search.audit_logs_search", kind: :internal) do
          es_query = Audit::Driftwood::Query.new_stafftools_query(
            phrase: phrase,
            current_user: @current_user,
          )
          es_query.execute
        end
        @results.deleted_users = ::AuditLogEntry.new_from_array(results).select do |log|
          log.data["id"] ||= log.user_id || log.org_id
          log.data["legal_hold"] = ::LegalHold.where(user_id: log.data["id"]).any?
          # Users might have been recreated already or the organization is soft deleted
          !::User.exists?(log.data["id"]) || SoftDeletedOrganization.exists?(organization_id: log.data["id"])
        end
      end
      @results.deleted_users.uniq! { |log| log.data["id"] }
    end

    def ignore_soft_deleted_organizations
      @results.users.delete_if { |user| soft_deleted_organization?(user) }
    end

    def soft_deleted_organization?(organization)
      !organization.nil? && organization.is_a?(::Organization) && organization.soft_deleted?
    end

    def sdn_screening_id_users_search
      GitHub.tracer.in_span("stafftools.searcher.sdn_screening_id_users_search", kind: :internal) do
        profile = ::AccountScreeningProfile.find_by(external_uuid: @query, owner_type: "User")
        @results.users << profile&.owner
      end
    end

    def fuzzy_repository_search
      return if @query =~ /\// # We have a name-with-owner query, don't bother with hitting ES
      GitHub.tracer.in_span("stafftools.searcher.fuzzy_repository_search", kind: :internal) do
        es_query = { query: {
          bool: {
            must: {
              multi_match: {
                query: @query,
                type: "most_fields",
                fields: %w[name^1.2 name.camel name.ngram^0.8],
                operator: "and",
              },
            },
          } },
          _source: false,
          size: 50,
        }
        query_params = { type: "repository" }
        index = ::Elastomer::Indexes::Repos.new
        response = GitHub.tracer.in_span("stafftools.searcher.fuzzy_repository_search.elasticsearch", kind: :internal) do
          index.search(es_query, query_params)
        end

        hits = response["hits"]["hits"]
        unless hits.empty?
          GitHub.tracer.in_span("stafftools.searcher.fuzzy_repository_search.mysql", kind: :internal) do
            ids = hits.map { |hit| hit["_id"] }
            id_sort = Arel.sql("field(id, #{ids.join(',')})")
            @results.repositories.concat ::Repository.where(id: ids).order(id_sort).includes(:owner, :mirror).all
          end
        end
      end
    end

    def repos_search
      GitHub.tracer.in_span("stafftools.searcher.repos_search", kind: :internal) do
        @results.repositories << ::Repository.with_name_with_owner(@query)
        @results.repositories << ::Repositories::Public.find_active(@query) if numeric_query?
      end
    end

    def integrations_search
      GitHub.tracer.in_span("stafftools.searcher.integrations_search", kind: :internal) do
        @results.integrations << ::Integration.find_by(id: @query) if numeric_query?
        @results.integrations << ::Integration.where(name: @query).first
        @results.integrations << ::Integration.where(slug: @query).first
      end
    end

    def integration_installations_search
      GitHub.tracer.in_span("stafftools.searcher.integration_installations_search", kind: :internal) do
        @results.integration_installations << ::IntegrationInstallation.find_by(id: @query)
      end
    end

    def businesses_search
      return if GitHub.single_business_environment?
      GitHub.tracer.in_span("stafftools.searcher.businesses_search", kind: :internal) do
        @results.businesses << ::Business.find_by(id: @query) if numeric_query?
        @results.businesses << ::Business.find_by(slug: @query)
      end
    end

    def sdn_screening_id_businesses_search
      return if GitHub.single_business_environment?
      GitHub.tracer.in_span("stafftools.searcher.sdn_screening_id_businesses_search", kind: :internal) do
        profile = ::AccountScreeningProfile.find_by(external_uuid: @query, owner_type: "Business")
        @results.businesses << profile&.owner
      end
    end

    def customers_search
      return if GitHub.single_business_environment?

      GitHub.tracer.in_span("stafftools.searcher.customers_search", kind: :internal) do
        @results.customers << ::Customer.find_by(id: @query) if numeric_query?
        @results.customers << ::Customer.find_by(zuora_account_number: @query)
        @results.customers << ::Customer.find_by(zuora_account_id: @query)
      end
    end

    def azure_subscription_search
      return if GitHub.single_business_environment?
      GitHub.tracer.in_span("stafftools.searcher.azure_subscription_search", kind: :internal) do
        customers = ::Customer.where(azure_subscription_id: @query).includes(:business, :organizations)
        @results.customers.concat(customers)
        customers.each do |customer|
          business = customer.business
          @results.businesses << business if business
        end
      end
      @results.users.concat(
        @results.customers.flat_map { |customer| customer.organizations }.compact
      )
    end

    def fuzzy_businesses_search
      return if GitHub.single_business_environment?

      GitHub.tracer.in_span("stafftools.searcher.fuzzy_businesses_search", kind: :internal) do
        query = ::Search::Queries::EnterpriseQuery.new query: @query
        results = query.execute
        unless results.empty?
          ids = results.map { |hit| hit["_id"] }
          @results.businesses.concat(Business.where(id: ids).all)
        end
      end
    end

    def deleted_businesses_search
      return if GitHub.single_business_environment?
      GitHub.tracer.in_span("stafftools.searcher.deleted_businesses_search", kind: :internal) do
        @results.deleted_businesses = ::Business.deleted.for_query(@query)
      end
    end

    def numeric_query?
      return @numeric_query if defined? @numeric_query
      @numeric_query = /\A\d+\z/.match?(@query)
    end
  end
end
