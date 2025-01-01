# typed: true
# frozen_string_literal: true

module Stafftools
  class Searcher
    include AuditLogHelper
    attr_reader :query, :results

    GPG_KEY_PATTERN = /\A[A-F0-9]{16}\z/i
    StafftoolsSearchResults = Struct.new(
      :users, :businesses, :deleted_businesses, :customers, :repositories, :gists,
      :oauth_app_user_counts, :oauth_apps, :integrations,
      :integration_installations, :fuzzy_users, :deleted_users, :renamed_user, :teams,
      :old_name, :gpg_keys, :gpg_key_users, :public_key, :oauth_access, :oauth_application, :integration, :hook) do
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
        end
      end

    def initialize(query, current_user)
      @results = StafftoolsSearchResults.new
      @query = (query || "").strip
      @current_user = current_user
    end

    def search_for_gpg_key
      if @query =~ GPG_KEY_PATTERN
        key_id = [@query.downcase].pack("H*")
        @results.gpg_keys = ::GpgKey.where(key_id: key_id)

        @results.gpg_key_users = @results.gpg_keys.map { |k| k.user }
      end
      self
    end

    def search_for_users
      search_for_gpg_key if @results.gpg_key_users.nil?
      standard_user_search
      coupon_users_search
      spammy_users_search
      deleted_users_search
      ignore_soft_deleted_organizations
      sdn_screening_id_users_search
      @results.users.uniq!
      @results.users.compact!
      self
    end

    def search_for_businesses
      businesses_search
      fuzzy_businesses_search
      deleted_businesses_search
      sdn_screening_id_businesses_search
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
      @results.teams << ::Team.find_by(id: @query) if numeric_query?
      if @query.count("/") == 1
        org, team = @query.split("/")
        @results.teams += ::Team.joins(:organization).where(users: { login: org }).where(slug: team)
      end
      @results.teams.uniq!
      @results.teams.compact!
      self
    end

    def search_for_renamed_users
      # We can't query for "action:user.rename" because it's indexed with the
      # new name only.
      phrase = "(user:#{@query} OR org:#{@query})"
      if driftwood_ade_query?(@current_user)
        phrase = "webevents | where user == '#{@query}' or org == '#{@query}'"
      end
      es_query = Audit::Driftwood::Query.new_stafftools_query(
        phrase: phrase,
        current_user: @current_user,
      )
      results = es_query.execute
      logs = ::AuditLogEntry.new_from_array(results)
      if (log = logs.find { |l| l.hit[:org]&.downcase == @query.downcase || l.hit[:user]&.downcase == @query.downcase })
        id = log.hit[:org] == @query ? log.org_id : log.user_id
        @results.renamed_user = ::User.find_by(id: id)
        @results.old_name = @query
      end
      self
    end

    def search_for_repositories
      fuzzy_repository_search
      repos_search
      @results.repositories.uniq!
      @results.repositories.compact!
      self
    end

    def search_for_gists
      @results.gists << ::Gist.with_name_with_owner(@query, nil, true)
      @results.gists << ::Gist.find_by(repo_name: @query)
      @results.gists.uniq!
      @results.gists.compact!
      self
    end

    def search_for_oauth_application
      cond = if numeric_query?
        ["id = ? OR name = ?", @query, @query]
      else
        { name: @query }
      end
      apps = ::OauthApplication.where(cond)
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
      self
    end

    def search_for_integrations
      integrations_search
      integration_installations_search if numeric_query?
      @results.integration_installations.uniq!
      @results.integrations.uniq!
      @results.integration_installations.compact!
      @results.integrations.compact!
      self
    end

    # Only handling a few key cases here, that are commonly logged in the GitHub Actions toolchain
    def search_by_global_relay_id
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
      self
    end

    def search_for_hook
      @results.hook = Hook.find_by(id: @query) if numeric_query?
      self
    end

    def search_for_public_key
      @results.public_key = ::PublicKey.find_by(fingerprint_sha256: @query.delete_prefix("SHA256:"))
      self
    end

    def search_for_oauth_access_token
      return self unless OauthAccessTokens::Domain.matches_pattern?(@query)
      hashed_token = OauthAccessTokens::Domain.hash_token(@query)
      found_access = OauthAccessTokens.domain.by_hash(hashed_token)
      @results.oauth_access = OauthAccessTokens.domain.by_hash(hashed_token)
      self
    end

    def search_for_oauth_application_by_key
      return self unless OauthAccess::ClientId.client_id?(@query)
      @results.oauth_application = ::OauthApplication.where(key: @query).first
      self
    end

    def search_for_integration_by_key
      return self unless Integration.client_id?(@query)
      @results.integration = ::Integration.find_by(key: @query)
      self
    end

    private

    def user_search_scope
      ::User.without_soft_deleted_organizations
    end

    def standard_user_search
      @results.users = if @query =~ /@/
        u = T.let([], T.untyped)
        u << ::User.find_by_email(@query)
        u += ::User.all_with_profile_email(@query)
        u += user_search_scope.where(gravatar_email: @query).where.not(type: :mannequin).to_a
        u += user_search_scope.where(organization_billing_email: @query).to_a
        external_emails = ::BillingExternalEmail.where(email: @query, owner_type: "User")
        external_emails.each { |external_email| u += ::User.where(id: external_email.owner_id).to_a }
        u
      elsif GitHub.multi_tenant_enterprise?
        if contains_tenant_suffix?(@query)
          u = T.let(::User.where(login: @query).to_a, T::Array[T.nilable(::User)])
        else
          u = T.let(::User.where(display_login: @query).to_a, T::Array[T.nilable(::User)])
        end

        u << ::User.find_by(id: @query) if numeric_query?

        key_users = @results.gpg_key_users
        u += key_users if key_users
        u
      else
        u = T.let(user_search_scope.where(login: @query).to_a, T::Array[T.nilable(::User)])
        u << ::User.find_by(id: @query) if numeric_query?

        key_users = @results.gpg_key_users
        u += key_users if key_users
        u
      end
    end

    # Returns true if the query contains a tenant suffix.
    def contains_tenant_suffix?(query)
      # Check if the query contains a either a tenant suffix or part of a tenant suffix indicated by the presence of an underscore.
      return true if query.include?("_")

      false
    end

    def coupon_users_search
      coupon = ::Coupon.find_by_code(@query)
      @results.users += coupon.users if coupon
    end

    # spammy users are _not_ in the search index, so we are doing a fuzzy
    # search in addition to the normal user searches above
    def spammy_users_search
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

    def deleted_users_search
      # Find deleted users
      user_or_org_delete = "(action:user.delete OR action:org.delete OR action:org.soft_delete OR action:org.async_delete OR action:org.destroy)"
      phrase = if numeric_query?
        "(user:#{@query} OR org:#{@query} OR user_id:#{@query} OR org_id:#{@query}) AND #{user_or_org_delete}"
      elsif @query =~ /@/
        "(data.email:#{@query}) AND #{user_or_org_delete}"
      else
        "(user:#{@query} OR org:#{@query}) AND #{user_or_org_delete}"
      end

      if driftwood_ade_query?(@current_user)
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

      es_query = Audit::Driftwood::Query.new_stafftools_query(
        phrase: phrase,
        current_user: @current_user,
      )
      results = es_query.execute
      @results.deleted_users = ::AuditLogEntry.new_from_array(results).select do |log|
        log.data["id"] ||= log.user_id || log.org_id
        log.data["legal_hold"] = ::LegalHold.where(user_id: log.data["id"]).any?
        # Users might have been recreated already or the organization is soft deleted
        !::User.exists?(log.data["id"]) || SoftDeletedOrganization.exists?(organization_id: log.data["id"])
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
      profile = ::AccountScreeningProfile.find_by(external_uuid: @query, owner_type: "User")
      @results.users << profile&.owner
    end

    def fuzzy_repository_search
      return if @query =~ /\// # We have a name-with-owner query, don't bother with hitting ES
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
      response = index.search(es_query, query_params)

      hits = response["hits"]["hits"]
      unless hits.empty?
        ids = hits.map { |hit| hit["_id"] }
        id_sort = Arel.sql("field(id, #{ids.join(',')})")
        @results.repositories.concat ::Repository.where(id: ids).order(id_sort).includes(:owner, :mirror).all
      end
    end

    def repos_search
      @results.repositories << ::Repository.with_name_with_owner(@query)
      @results.repositories << ::Repositories::Public.find_active(@query) if numeric_query?
    end

    def integrations_search
      @results.integrations << ::Integration.find_by(id: @query) if numeric_query?
      @results.integrations << ::Integration.where(name: @query).first
    end

    def integration_installations_search
      @results.integration_installations << ::IntegrationInstallation.find_by(id: @query)
    end

    def businesses_search
      return if GitHub.single_business_environment?

      @results.businesses << ::Business.find_by(id: @query) if numeric_query?
      @results.businesses << ::Business.find_by(slug: @query)
    end

    def sdn_screening_id_businesses_search
      return if GitHub.single_business_environment?

      profile = ::AccountScreeningProfile.find_by(external_uuid: @query, owner_type: "Business")
      @results.businesses << profile&.owner
    end

    def customers_search
      return if GitHub.single_business_environment?

      @results.customers << ::Customer.find_by(id: @query) if numeric_query?
      @results.customers << ::Customer.find_by(zuora_account_number: @query)
      @results.customers << ::Customer.find_by(zuora_account_id: @query)
    end

    def fuzzy_businesses_search
      return if GitHub.single_business_environment?

      query = ::Search::Queries::EnterpriseQuery.new query: @query
      results = query.execute
      unless results.empty?
        ids = results.map { |hit| hit["_id"] }
        @results.businesses.concat(Business.where(id: ids).all)
      end
    end

    def deleted_businesses_search
      return if GitHub.single_business_environment?

      @results.deleted_businesses = ::Business.deleted.for_query(@query)
    end

    def numeric_query?
      return @numeric_query if defined? @numeric_query
      @numeric_query = /\A\d+\z/.match?(@query)
    end
  end
end
