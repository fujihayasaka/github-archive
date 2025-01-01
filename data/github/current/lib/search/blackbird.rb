# typed: strict
# frozen_string_literal: true
require "blackbird"
require "blackbird-client"

module Search
  module Blackbird
    ENABLE_CODE_EMBEDDING_EXPERIMENT = "blackbird_enable_code_embedding"
    ENABLE_DOCS_EMBEDDING_EXPERIMENT = "blackbird_enable_markdown_embedding"

    extend T::Sig
    autoload :AnalysisClient, "search/blackbird/analysis_client"
    autoload :Publisher, "search/blackbird/publisher"

    class Client
      extend T::Sig
      extend T::Helpers

      SERVICE_URL         = T.let(GitHub.blackbird_url, String)
      SERVICE_NAME        = "blackbird"
      DEFAULT_TIMEOUT     = 10.0
      ACCESS_TOKEN_KIND_API = "API"

      AUTO_SNIPPET_MODE_EXPERIMENT = 11
      USE_LAB_MIDDLEWARE_EXPERIMENT = 14
      USE_NEW_PAGINATION_EXPERIMENT = 16

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

      Actor = T.type_alias do
        T.any(::Blackbird::Query::V1::Actor, ::Blackbird::Query::V2::Actor)
      end

      sig do
        params(
          user: User,
          user_session: UserSession,
        ).returns(Actor)
      end
      def self.actor(user, user_session)
        token = GitHub::Authentication::SignedAuthToken.generate(
          session: user_session,
          scope: "Blackbird::AccessToken",
          expires: 1.hour.from_now
        )
        if GitHub.flipper[:blackbird_use_v2_mw].enabled?(user)
          ::Blackbird::Query::V2::Actor.new(
            actor_id: user.id,
            access_token: token,
            request_ip: user_session.ip,
            session_id: user_session.id.to_s,
          )
        else
          ::Blackbird::Query::V1::Actor.new(
            actor_id: user.id,
            access_token: token,
            request_ip: user_session.ip,
            session_id: user_session.id.to_s,
          )
        end
      end

      sig do
        params(
          user: User,
          ip_address: T.nilable(String),
          token: String,
        ).returns(Actor)
      end
      def self.api_actor(user, ip_address, token)
        if GitHub.flipper[:blackbird_use_v2_mw].enabled?(user)
          ::Blackbird::Query::V2::Actor.new(
            actor_id: user.id,
            access_token: token,
            request_ip: ip_address,
            session_id: AuthenticationToken.hash_token(token),
            access_token_kind: ACCESS_TOKEN_KIND_API,
          )
        else
          ::Blackbird::Query::V1::Actor.new(
            actor_id: user.id,
            access_token: token,
            request_ip: ip_address,
            session_id: AuthenticationToken.hash_token(token),
            access_token_kind: ACCESS_TOKEN_KIND_API,
          )
        end
      end

      sig { params(actor: Actor).returns(T.nilable(T::Hash[String, T.anything])) }
      def self.warm_caches(actor)
        req = ::Blackbird::Query::V1::WarmCachesRequest.new(actor: actor)
        if GitHub.blackbird_use_fake_data
          resp = ::Blackbird::Query::V1::WarmCachesResponse.new
          return resp.to_h
        end

        resp = client.warm_caches(req)
        if resp.error
          return nil
        end

        resp.data.to_h
      end

      sig do
        params(
          actor: Actor,
          nwo: String,
          tenant: T.untyped,
        ).returns(Twirp::ClientResp[::Blackbird::Query::V1::GetRepositoryResponse])
      end
      def self.get_repository(actor, nwo, tenant)
        req = ::Blackbird::Query::V1::GetRepositoryRequest.new(actor: actor, nwo: nwo, tenant: tenant)
        if GitHub.blackbird_use_fake_data
          resp = Twirp::ClientResp.new
          resp.data = ::Blackbird::Query::V1::GetRepositoryResponse.new(
            repository: ::Blackbird::Query::V1::Repository.new(
              id: 1,
              owner_id: 2,
              owner_login: "colinwm",
              name: "dotfiles",
              is_public: true,
              repo_score: 1,
            ),
            serving_corpus: ::Blackbird::Query::V1::Corpus.new(
              cluster_name: "zeta",
              corpus_name: "blue",
              epoch_id: 123,
              serving_offset: 54321,
            ),
            snapshot_entries: [
              ::Blackbird::Query::V1::SnapshotEntry.new(
                entry_id: 123,
                serving_offset: 54322,
                experiments: {
                  "blackbird_enable_code_embedding" => "1",
                }
              ),
              ::Blackbird::Query::V1::SnapshotEntry.new(
                entry_id: 122,
                serving_offset: 54000,
                experiments: {
                  "blackbird_enable_code_embedding" => "1",
                }
              ),
            ],
          )
          return resp
        end

        client.get_repository(req)
      end

      sig { params(actor: Actor).returns(T.nilable(T::Hash[String, T.anything])) }
      def self.refresh_auth_caches(actor)
        req = ::Blackbird::Query::V1::RefreshAuthCachesRequest.new(actor: actor)
        if GitHub.blackbird_use_fake_data
          resp = ::Blackbird::Query::V1::RefreshAuthCachesResponse.new
          return resp.to_h
        end

        resp = client.refresh_auth_caches(req)
        if resp.error
          return nil
        end

        resp.data.to_h
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
          data = JSON.parse(File.read("#{__dir__}/blackbird_response.json"))
          if data.key?(args[:query])
            data = data[args[:query]]
          else
            data = data[data.keys.sample]
          end

          Twirp::ClientResp::new(
            data: ::Blackbird::Query::V1::LegacyQueryResponse::decode_json(data.to_json),
            error: nil,
          )
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
        T.any(::Blackbird::Query::V1::FrontendQueryResponse, ::Blackbird::Query::V2::FrontendQueryResponse)
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


        context = if GitHub.flipper[:blackbird_use_v2_mw].enabled?(user)
          set_query_source_v2(args, "web")
        else
          set_query_source(args, "web")
        end

        req = if GitHub.flipper[:blackbird_use_v2_mw].enabled?(user)
          ::Blackbird::Query::V2::FrontendQueryRequest.new(args)
        else
          ::Blackbird::Query::V1::FrontendQueryRequest.new(args)
        end

        # All dotcom traffic should have the snippet_mode=auto experiment enabled
        req.experiments["snippet_mode"] = "auto" unless req.experiments.has_key?("snippet_mode")

        resp = if GitHub.blackbird_use_fake_data
          data = JSON.parse(File.read("#{__dir__}/blackbird_response.json"))
          if data.key?(args[:query])
            data = data[args[:query]]
          else
            data = data[data.keys.sample]
          end

          # If you wish to emulate Blackbird returning a hard error then include an "error" key in the mock response.
          T.let(Twirp::ClientResp::new(
            data: ::Blackbird::Query::V1::FrontendQueryResponse::decode_json(data.except("error").to_json),
            error: data["error"] ? Twirp::Error.new(data.dig("error", "code"), data.dig("error", "message")) : nil,
          ), Twirp::ClientResp[T.nilable(FrontendQueryResponse)])
        elsif GitHub.flipper[:blackbird_use_v2_mw].enabled?(user)
          GitHub.dogstats.increment("search.query.total", tags: datadog_tags(user: user, is_count: false, context: context))
          GitHub.dogstats.time("search.query.time", tags: datadog_tags(user: user, is_count: false, context: context)) do
            v2_client.frontend_query(req)
          end
        elsif req.experiments.delete("use_lab_middleware")
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

      # Sets `:query_source` on `args` based on calling `get_context`.
      # Returns the context.
      sig do
        params(
          args: T::Hash[Symbol, T.untyped],
          default: String,
        ).returns(T.untyped)
      end
      def self.set_query_source_v2(args, default)
        context = get_context(args, default)
        args[:query_source] ||= case context
        when "graphql"
          ::Blackbird::Query::V2::QuerySource::QUERY_SOURCE_GRAPHQL_API
        when "api"
          ::Blackbird::Query::V2::QuerySource::QUERY_SOURCE_LEGACY_API
        else # "web" and everything else
          ::Blackbird::Query::V2::QuerySource::QUERY_SOURCE_FRONTEND
        end
        context
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
      sig { params(user: T.untyped, is_count: T::Boolean, context: String, error_code: T.nilable(T.any(String, Symbol))).returns(T::Array[String]) }
      def self.datadog_tags(user:, is_count:, context:, error_code: nil)
        logged_in = user.present? ? "true" : "false"
        query_type = is_count ? "count" : "search"
        spammy_actor = user&.spammy? ? "true" : "false"
        mw_version = GitHub.flipper[:blackbird_use_v2_mw].enabled?(user) ? "v2" : "v1"

        tags = [
          # we don't have a good way to see if a query is scoped, and doesn't work from repo endpoints so we assume everything is global
          "context:#{context}.global",
          "index:blackbird_code_search",
          "logged_in:#{logged_in}",
          "query_type:#{query_type}",
          "search_scope:standard",
          "spammy_actor:#{spammy_actor}",
          "mw_version:#{mw_version}"
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

        if GitHub.blackbird_use_fake_data
          data = JSON.parse(File.read("#{__dir__}/blackbird_suggest_response.json"))

          resp = Twirp::ClientResp::new(
            data: ::Blackbird::Query::V1::SuggestResponse::decode_json(data.to_json),
            error: nil,
          )
        else
          resp = client.suggest(req)
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
          owner += "_" + GitHub::CurrentTenant.get.shortcode if GitHub.multi_tenant_enterprise?

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
        BlackbirdOnboardReposJob.perform_later(T.must(user.id), repo_ids.to_a) unless repo_ids.empty?

        if !owner_logins.empty? && GitHub.flipper[:blackbird_lazy_indexing_orgs].enabled?
          BlackbirdOnboardJob.perform_later(owner_logins.to_a)
        end
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

      sig { returns ::Blackbird::Query::V2::QueryAPIClient }
      def self.v2_client
        @v2_client ||= T.let(
          ::Blackbird::Query::V2::QueryAPIClient.new(build_connection(GitHub.blackbird_mw_query_url)),
          T.nilable(::Blackbird::Query::V2::QueryAPIClient)
        )
      end
    end

    # Setting blackbird experiments for a repo alters indexing behavior. Right now we have two ongoing experiments:
    #   :blackbird_enable_code_embedding - Blackbird will compute and index embeddings for code in the repo.
    #   :blackbird_enable_markdown_embedding - Blackbird will compute and index embeddings for markdown docs in the
    #   repo.
    sig do
      params(
        cir: T.nilable(CopilotIndexedRepositories)
      ).returns(T::Hash[String, String])
    end
    def self.experiments(cir)
      experiments = {}
      return experiments unless cir.present?
      experiments[ENABLE_CODE_EMBEDDING_EXPERIMENT] = "1" unless cir.markdown_only
      experiments[ENABLE_DOCS_EMBEDDING_EXPERIMENT] = "1" if cir.markdown_only
      experiments
    end
  end
end
