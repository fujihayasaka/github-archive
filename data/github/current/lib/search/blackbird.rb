# typed: strict
# frozen_string_literal: true

require "blackbird-client"

module Search
  module Blackbird
    TOKEN_SCOPE = "Blackbird::AccessToken"
    autoload :AnalysisClient, "search/blackbird/analysis_client"
    autoload :Publisher, "search/blackbird/publisher"

    class Client
      extend T::Helpers

      SERVICE_NAME        = "blackbird"
      DEFAULT_TIMEOUT     = 10.0

      # ACCESS_TOKEN_KIND_API includes legacy PAT (OauthAccess), fine-grained PAT (UserProgrammaticAccess), and integrations (IntegrationInstallation).
      ACCESS_TOKEN_KIND_API = "API"
      # ACCESS_TOKEN_KIND_WEB includes SignedAuthTokens based on user sessions.
      ACCESS_TOKEN_KIND_WEB = "WEB"

      SPAMMY_QUERY_ERROR = T.let({
        "type": :ERROR_TYPE_ACTOR_NOT_AUTHORIZED,
        "message": "Your user account has been flagged, and cannot search code",
        "ranges": [],
        "missing_or_inaccessible_repo_org_nwo": ""
      }, T::Hash[String, T.anything])

      sig do
        params(tenant: T.untyped)
        .returns(T.nilable(T::Hash[Symbol, T.anything]))
      end
      def self.tenant(tenant)
        return nil unless tenant
        {
          tenant_id: tenant.id,
          slug: tenant.slug,
          shortcode: tenant.shortcode,
        }
      end

      Pb = ::Blackbird::Query::V1

      Actor = T.type_alias do
        ::Blackbird::Query::V1::Actor
      end

      sig do
        params(
          user: User,
          user_session: UserSession,
          remote_ip: String,
        ).returns(Actor)
      end
      def self.actor(user, user_session, remote_ip)
        token = GitHub::Authentication::SignedAuthToken.generate(
          session: user_session,
          scope: Search::Blackbird::TOKEN_SCOPE,
          expires: 1.hour.from_now
        )
        ::Blackbird::Query::V1::Actor.new(
          actor_id: user.id,
          access_token: token,
          request_ip: remote_ip,
          session_id: user_session.id.to_s,
          access_token_kind: ACCESS_TOKEN_KIND_WEB,
        )
      end

      sig do
        params(
          user: User,
          ip_address: T.nilable(String),
          token: String,
        ).returns(Actor)
      end
      def self.api_actor(user, ip_address, token)
        ::Blackbird::Query::V1::Actor.new(
          actor_id: user.id,
          access_token: token,
          request_ip: ip_address,
          session_id: ServerToServerTokens::Domain.hash_token(token),
          access_token_kind: ACCESS_TOKEN_KIND_API,
        )
      end

      sig do
        params(repository_ids: T::Array[Integer]).returns(Twirp::ClientResp[::Blackbird::Query::V1::GetRepositoryStatusResponse])
      end
      def self.get_repository_status(repository_ids)
        if GitHub.blackbird_use_fake_data
          return self.fake_response(::Blackbird::Query::V1::GetRepositoryStatusResponse, repository_ids.join(","))
        end

        client.get_repository_status(::Blackbird::Query::V1::GetRepositoryStatusRequest.new(repository_ids: repository_ids))
      end

      sig do
        params(
          user: User,
          args: T::Hash[Symbol, T.untyped],
        ).returns(T.nilable(T::Hash[String, T.anything]))
      end
      def self.count(user, args)
        # TODO: Support :query_source for a CountRequest
        context = get_context(args, "web")
        req = ::Blackbird::Query::V1::CountRequest.new(args)

        if GitHub.blackbird_use_fake_data
          return {
            failed: false,
            count: 12345,
            mode: 1,
          }
        end

        resp = T.let(nil, T.untyped)
        GitHub.dogstats.increment("search.query.total", tags: datadog_tags(user: user, is_count: true, context: context))
        GitHub.dogstats.time("search.query.time", tags: datadog_tags(user: user, is_count: true, context: context)) do
          resp = client.count(req)
        end

        if resp.error
          GitHub.dogstats.increment("search.query.errors", tags: datadog_tags(user: user, is_count: true, context: context, error_code: resp.error.code))
          return {
            failed: true
          }
        else
          GitHub.dogstats.increment("search.query.success", tags: datadog_tags(user: user, is_count: true, context: context))
          GitHub.dogstats.distribution("search.query.result_count", resp.data.count, tags: datadog_tags(user: user, is_count: true, context: context))
        end

        {
          failed: false,
          count: resp.data.count,
          mode: resp.data.mode,
        }
      end

      sig do
        params(
          user: User,
          args: T::Hash[Symbol, T.untyped],
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def self.legacy_query(user, args)
        # NOTE: As long as a query is protected by the rate limiter, spammy users should get a rate limit of 0
        # and not hit this code. I'm leaving it in as a backstop.
        if user.spammy?
          return {
            results: [],
            errors: [SPAMMY_QUERY_ERROR],
            page: 0,
            page_count: 0,
            result_count: 0,
            failed: false,
            query_id: "",
            results_incomplete: false,
          }
        end

        # TODO: Support :query_source for a LegacyQueryRequest
        context = get_context(args, "api")

        resp = if GitHub.blackbird_use_fake_data
          fake_response(::Blackbird::Query::V1::LegacyQueryResponse, args[:query])
        else
          req = ::Blackbird::Query::V1::LegacyQueryRequest.new(args)
          req.experiments["pagination"] = "1"
          GitHub.dogstats.increment("search.query.total", tags: datadog_tags(user: user, is_count: false, context: context))
          GitHub.dogstats.time("search.query.time", tags: datadog_tags(user: user, is_count: false, context: context)) do
            client.legacy_query(req)
          end
        end

        if resp.error
          GitHub.dogstats.increment("search.query.errors", tags: datadog_tags(user: user, is_count: false, context: context, error_code: resp.error.code))
          return {
            failed: true,
            error_message: resp.error
          }
        else
          GitHub.dogstats.increment("search.query.success", tags: datadog_tags(user: user, is_count: false, context: context))
          GitHub.dogstats.distribution("search.query.result_count", resp.data.result_count, tags: datadog_tags(user: user, is_count: false, context: context))
        end

        GlobalInstrumenter.instrument "search.execute", {
          variant: "blackbird-legacy-api",
          actor: user,
          query: args[:query],
          escaped_query: args[:query],
          search_server_took_ms: (resp.data&.metadata&.timing&.overall&.nanos || 0) / 1000,
          search_server_timed_out: resp.data&.metadata&.had_shard_failure,
          page_number: resp.data.page,
          total_results: resp.data.result_count,
          search_type: ["code"],
          search_context: "api.global",
          originating_request_id: GitHub.context[:request_id],
          query_id: resp.data&.metadata&.query_id,
        }

        {
          results: resp.data.results.map(&:to_h),
          errors: resp.data.query_errors.map(&:to_h),
          page: resp.data.page,
          page_count: resp.data.page_count,
          result_count: resp.data.result_count,
          failed: false,
          query_id: resp.data&.metadata&.query_id,
          results_incomplete: resp.data&.metadata&.had_shard_failure
        }
      end

      FrontendQueryResponse = T.type_alias do
        ::Blackbird::Query::V1::FrontendQueryResponse
      end

      sig do
        params(
          user: User,
          cap_filter: T.untyped,
          args: T::Hash[Symbol, T.untyped],
        ).returns(T::Hash[Symbol, T.anything])
      end
      def self.query(user, cap_filter, args)
        # NOTE: As long as a query is protected by the rate limiter, spammy users should get a rate limit of 0
        # and not hit this code. I'm leaving it in as a backstop.
        if user.spammy?
          return {
            results: [],
            errors: [SPAMMY_QUERY_ERROR],
            page: 0,
            page_count: 0,
            result_count: 0,
            facets: [],
            failed: false,
            protected_organization_ids: [],
            results_incomplete: false,
          }
        end

        context = set_query_source(args, "web")

        req = ::Blackbird::Query::V1::FrontendQueryRequest.new(args)

        # All dotcom traffic should have the snippet_mode=auto experiment enabled
        req.experiments["snippet_mode"] = "auto" unless req.experiments.has_key?("snippet_mode")

        resp = if GitHub.blackbird_use_fake_data
          # If you wish to emulate Blackbird returning a hard error then search for "returns-error"
          case args[:query]
          when "returns-error"
            Twirp::ClientResp::new(error: Twirp::Error.unavailable("Blackbird is unavailable"))
          when "returns-quota-exhaustion-error"
            Twirp::ClientResp::new(error: Twirp::Error.resource_exhausted("query rejected because the user is out of quota"))
          else
            fake_response(::Blackbird::Query::V1::FrontendQueryResponse, args[:query])
          end
        elsif user.feature_enabled?(:blackbird_use_lab)
          GitHub.dogstats.increment("search.query.total", tags: datadog_tags(user: user, is_count: false, context: context))
          GitHub.dogstats.time("search.query.time", tags: datadog_tags(user: user, is_count: false, context: context)) do
            lab_client.frontend_query(req)
          end
        else
          GitHub.dogstats.increment("search.query.total", tags: datadog_tags(user: user, is_count: false, context: context))
          GitHub.dogstats.time("search.query.time", tags: datadog_tags(user: user, is_count: false, context: context)) do
            client.frontend_query(req)
          end
        end

        if resp.error || resp.data.nil?
          GitHub.dogstats.increment("search.query.errors", tags: datadog_tags(user: user, is_count: false, context: context, error_code: resp.error&.code))
          return {
            failed: true,
            error_message: resp.error
          }
        else
          GitHub.dogstats.increment("search.query.success", tags: datadog_tags(user: user, is_count: false, context: context))
          GitHub.dogstats.distribution("search.query.result_count", resp.data&.result_count, tags: datadog_tags(user: user, is_count: false, context: context))
        end

        lazy_index(user, cap_filter, resp.data.query_errors)

        # Log the search
        GlobalInstrumenter.instrument "search.execute", {
          variant: "blackbird-dotcom",
          actor: user,
          query: args[:query],
          escaped_query: args[:query],
          search_server_took_ms: (resp.data.metadata&.timing&.overall&.nanos || 0) / 1000,
          search_server_timed_out: resp.data.metadata&.had_shard_failure,
          page_number: resp.data.page,
          total_results: resp.data.result_count,
          search_type: ["code"],
          search_context: "web.global",
          originating_request_id: GitHub.context[:request_id],
          query_id: resp.data.metadata&.query_id,
        }

        {
          results: resp.data.results.map(&:to_h),
          errors: resp.data.query_errors.map(&:to_h),
          page: resp.data.page,
          page_count: resp.data.page_count,
          result_count: resp.data.result_count,
          facets: resp.data.facets.map(&:to_h),
          failed: false,
          protected_organization_ids: resp.data&.protected_organization_ids&.map(&:to_i),
          query_id: resp.data&.metadata&.query_id,
          results_incomplete: resp.data&.metadata&.had_shard_failure,
          metadata: (user.site_admin? || user.metadata&.is_staff?) ? resp.data.metadata&.to_h : nil
        }

      end

      sig do
        params(
          user: User,
          actor: ::Blackbird::Query::V1::Actor,
          symbol_name: String,
          repo: Repository,
          commit_oid: String,
          path: String,
          row: Integer,
          col: Integer,
          ref: String,
          language: String,
          symbol_kind: T.any(Integer, Symbol),
        ).returns(T.nilable(Twirp::ClientResp[::Blackbird::Query::V1::TextDocumentDefinitionResponse]))
      end
      def self.text_document_definition(user:, actor:, symbol_name:, repo:, commit_oid:, path:, row:, col:, ref:, language:, symbol_kind:)
        req = ::Blackbird::Query::V1::TextDocumentDefinitionRequest.new(
          actor:,
          tenant: self.pb_tenant,
          body: ::Blackbird::Query::V1::AlephLocationRequest.new(
            symbol_name:,
            commit_oid:,
            path:,
            position: ::Blackbird::Query::V1::AlephPosition.new(line: row, character: col),
            repository_owner: repo.owner&.name,
            repository_name: repo.name,
            repository_id: repo.id,
            ref:,
            language:,
            symbol_kind:
          )
        )

        resp = self.client.text_document_definition(req)

        if resp.error || resp.data.nil?
          GitHub.dogstats.increment("search.query.errors", tags: datadog_tags(user: user, is_count: false, context: "web", error_code: resp.error&.code))
        end

        resp
      end

      sig do
        params(
          user: User,
          actor: ::Blackbird::Query::V1::Actor,
          symbol_name: String,
          repo: Repository,
          commit_oid: String,
          path: String,
          row: Integer,
          col: Integer,
          ref: String,
          language: String,
          symbol_kind: T.any(Integer, Symbol),
        ).returns(T.nilable(Twirp::ClientResp[::Blackbird::Query::V1::TextDocumentReferencesResponse]))
      end
      def self.text_document_references(user:, actor:, symbol_name:, repo:, commit_oid:, path:, row:, col:, ref:, language:, symbol_kind:)
        req = ::Blackbird::Query::V1::TextDocumentReferencesRequest.new(
          actor:,
          tenant: self.pb_tenant,
          body: ::Blackbird::Query::V1::AlephLocationRequest.new(
            symbol_name:,
            commit_oid:,
            path:,
            position: ::Blackbird::Query::V1::AlephPosition.new(line: row, character: col),
            repository_owner: repo.owner&.name,
            repository_name: repo.name,
            repository_id: repo.id,
            ref:,
            language:,
            symbol_kind:
          )
        )
        resp = self.client.text_document_references(req)

        if resp.error || resp.data.nil?
          GitHub.dogstats.increment("search.query.errors", tags: datadog_tags(user: user, is_count: false, context: "web", error_code: resp.error&.code))
        end

        resp
      end

      # Sets `:query_source` on `args` based on calling `get_context`.
      # Returns the context.
      sig do
        params(
          args: T::Hash[Symbol, T.untyped],
          default: String,
        ).returns(T.untyped)
      end
      def self.set_query_source(args, default)
        context = get_context(args, default)
        args[:query_source] ||= case context
        when "graphql"
          ::Blackbird::Query::V1::QuerySource::QUERY_SOURCE_GRAPHQL_API
        when "api"
          ::Blackbird::Query::V1::QuerySource::QUERY_SOURCE_LEGACY_API
        else # "web" and everything else
          ::Blackbird::Query::V1::QuerySource::QUERY_SOURCE_FRONTEND
        end
        context
      end

      # Get and delete the `:context` key from args or return `default` if args[:context] is not set.
      sig do
        params(
          args: T::Hash[Symbol, T.untyped],
          default: String,
        ).returns(T.untyped)
      end
      def self.get_context(args, default)
        args.delete(:context) || default
      end

      # gets an array of tags for datadog.
      # context should be "api" or "web"
      sig { params(user: User, is_count: T::Boolean, context: String, error_code: T.nilable(T.any(String, Symbol))).returns(T::Array[String]) }
      def self.datadog_tags(user:, is_count:, context:, error_code: nil)
        logged_in = user.present? ? "true" : "false"
        query_type = is_count ? "count" : "search"
        spammy_actor = user.spammy? ? "true" : "false"

        tags = [
          # we don't have a good way to see if a query is scoped, and doesn't work from repo endpoints so we assume everything is global
          "context:#{context}.global",
          "index:blackbird_code_search",
          "logged_in:#{logged_in}",
          "query_type:#{query_type}",
          "search_scope:standard",
          "spammy_actor:#{spammy_actor}",
        ]

        if error_code.present?
          tags << "error:#{error_code}"
        end

        tags
      end

      sig do
        params(
          user: T.nilable(User),
          args: T::Hash[Symbol, T.untyped],
        ).returns(T::Hash[Symbol, T.anything])
      end
      def self.suggest(user, args)
        # NOTE: As long as a query is protected by the rate limiter, spammy users should get a rate limit of 0
        # and not hit this code. I'm leaving it in as a backstop.
        if user&.spammy?
          return {
            suggestions: [],
            queryErrors: [SPAMMY_QUERY_ERROR],
            failed: false,
          }
        end

        req = ::Blackbird::Query::V1::SuggestRequest.new(args)

        resp = if GitHub.blackbird_use_fake_data
          fake_response(::Blackbird::Query::V1::SuggestResponse, args[:query])
        else
          client.suggest(req)
        end

        failed = !!resp.error

        {
          suggestions: resp.data&.suggestions&.map(&:to_h),
          queryErrors: resp.data&.query_errors&.map(&:to_h),
          failed: failed,
        }
      end

      # If there's a query error for missing/inaccessible repos, check whether the repo actually exists. If it does,
      # then it isn't indexed, so rewrite the error message to that effect. Optionally kick of lazy indexing for
      # individual repos or user/org accounts based on these query errors.
      #
      # NB: N+1 db queries in the each are OK for now as we expect a small number of these errors (usually one).
      sig do
        params(
          user: User,
          cap_filter: T.untyped,
          query_errors: T.untyped,
        ).void
      end
      def self.lazy_index(user, cap_filter, query_errors)
        repo_ids = Set.new
        owner_logins = Set.new
        query_errors.each do |error|
          next unless error.type.to_s == "ERROR_TYPE_MISSING_INACCESSIBLE_REPO_ORG"
          owner, name = error.missing_or_inaccessible_repo_org_nwo.split("/")
          next unless owner
          owner += "_#{GitHub::CurrentTenant.get.shortcode}" if GitHub.multi_tenant_enterprise?

          if name
            # Only onboard this repo if it's readable by the user and accessible due to CAP/SAML.
            repo = Repository.find_by(name: name, owner_login: owner, active: true)
            next unless repo && repo.readable_by?(user)
            next if repo.organization && cap_filter.unauthorized_resource_ids([repo.organization], only: :saml).any?

            repo_ids << repo.id
          else
            # Must be an org name
            owner_logins << owner
          end

          suffix = if name && GitHub.flipper[:blackbird_lazy_indexing].enabled? || !name && GitHub.flipper[:blackbird_lazy_indexing_orgs].enabled?
            "is being indexed right now. Try again in a few minutes."
          else
            "has not been indexed yet. Try again later."
          end
          error.message = "This #{name ? 'repository' : 'account'}'s code #{suffix}"
        end

        return unless GitHub.flipper[:blackbird_lazy_indexing].enabled?
        BlackbirdOnboardReposJob.perform_later(user.id, repo_ids.to_a) unless repo_ids.empty?

        if !owner_logins.empty? && GitHub.flipper[:blackbird_lazy_indexing_orgs].enabled?
          BlackbirdOnboardJob.perform_later(owner_logins.to_a)
        end
      end

      sig { returns(T.nilable(::Blackbird::Query::V1::Tenant)) }
      def self.pb_tenant
        tenant = self.tenant(GitHub::CurrentTenant.get)
        ::Blackbird::Query::V1::Tenant.new(**tenant) if tenant
      end

      sig do
        params(msg_class: T.untyped, key: String).returns(Twirp::ClientResp[T.untyped])
      end
      def self.fake_response(msg_class, key)
        data = JSON.parse(File.read("#{__dir__}/mocks/#{msg_class.name.demodulize.underscore}.json"))
        data = data[key] || data[data.keys.first]
        Twirp::ClientResp::new(data: msg_class::decode_json(data.to_json))
      end

      sig { params(url: String).returns Faraday::Connection }
      def self.build_connection(url)
        Faraday.new(url: url) do |conn|
          conn.use GitHub::FaradayMiddleware::RequestID
          conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
          conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.blackbird_hmac_key
          conn.use GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME, options: {
            instrumenter: GitHub,
            sleep_window_seconds: 10,
            error_threshold_percentage: 5,
            window_size_in_seconds: 30,
            bucket_size_in_seconds: 5,
          }
          conn.options[:open_timeout] = DEFAULT_TIMEOUT # connection open timeout in seconds.
          conn.options[:timeout] = DEFAULT_TIMEOUT  # read timeout in seconds.
          conn.adapter :persistent_excon
        end
      end

      sig { returns ::Blackbird::Query::V1::QueryAPIClient }
      def self.lab_client
        @lab_client ||= T.let(
          ::Blackbird::Query::V1::QueryAPIClient.new(build_connection(GitHub.blackbird_lab_url)),
          T.nilable(::Blackbird::Query::V1::QueryAPIClient)
        )
      end

      sig { returns ::Blackbird::Query::V1::QueryAPIClient }
      def self.client
        @client ||= T.let(
          ::Blackbird::Query::V1::QueryAPIClient.new(build_connection(GitHub.blackbird_url)),
          T.nilable(::Blackbird::Query::V1::QueryAPIClient)
        )
      end
    end

    # Public: Converts a language name to the format used by Blackbird's code nav feature flipper format.
    #
    # language_name - language name to convert.
    #
    # Returns a symbol representing a feature flag (e.g. GitHub.flipper[:aleph_language_ruby]).
    sig { params(language_name: T.nilable(String)).returns(Symbol) }
    def self.convert_language_name(language_name)
      "aleph_language_#{clean_language_name(language_name)}".to_sym
    end

    # Public: Converts a language name to the format used by Blackbird's darkship code nav feature flipper format.
    #
    # language_name - language name to convert.
    #
    # Returns a symbol representing a feature flag (e.g. GitHub.flipper[:aleph_darkship_language_ruby]).
    sig { params(language_name: T.nilable(String)).returns(Symbol) }
    def self.convert_darkship_language_name(language_name)
      "aleph_darkship_language_#{clean_language_name(language_name)}".to_sym
    end

    # Public: Scrubs a Linguist language name to remove special symbols.
    #
    # language_name - language name to sanitize.
    #
    # Returns a sanitized string (e.g. Given "HTML+ERB" this method returns "html_erb").
    sig { params(language_name: T.nilable(String)).returns(T.nilable(String)) }
    def self.clean_language_name(language_name)
      return "csharp" if language_name == "C#"

      language_name&.gsub(INVALID_CHARS, "_")&.downcase
    end

    # Some characters are not valid for GitHub.flipper names.
    # This regex is used to remove invalid characters from Linguist language names
    # when converting a Linguist language name to the derived format used with GitHub.flipper.
    INVALID_CHARS = /[-+\s\.]/

    # Setting blackbird experiments for a repo alters indexing behavior.
    #   - blackbird_enable_code_embedding: blackbird will compute and index embeddings for code and markdown in the
    #     repo.
    sig do
      params(
        cir: T.nilable(CopilotIndexedRepositories)
      ).returns(T::Hash[String, String])
    end
    def self.experiments(cir)
      return {} unless cir.present?

      experiments = {}
      experiments["blackbird_enable_code_embedding"] = "1"
      experiments
    end
  end
end
