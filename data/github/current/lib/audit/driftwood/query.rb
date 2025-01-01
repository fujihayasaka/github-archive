# typed: true
# frozen_string_literal: true

module Audit
  module Driftwood
    class Query
      include Scientist
      extend Scientist
      extend Forwardable

      class DriftwoodQueryNotPermitted < StandardError; end

      PER_PAGE = 50

      attr_reader :business,
        :business_id,
        :current_user,
        :org,
        :org_id,
        :original_query,
        :driftwood_query,
        :per_page,
        :from_stafftools

      def_delegators :driftwood_query,
        :after,
        :after=,
        :before,
        :before=,
        :has_next_page?,
        :has_previous_page?,
        :total_count

      def initialize(args = {})
        @business = args[:business]
        @business_id = args[:business_id]
        @current_user = args[:current_user]
        @org = args[:org]
        @org_id = args[:org_id]

        @original_query = args[:original_query]
        @driftwood_query = args[:driftwood_query]

        @per_page = args.fetch(:per_page, PER_PAGE)
        if @driftwood_query.request.respond_to?(:per_page=)
          @driftwood_query.per_page = @per_page
        end

        if @original_query # git queries won't have an @original_query since we don't have that data in the legacy ES
          @original_query.per_page = @per_page
          configure_page_and_offset(args)
        end

        @business ||= Business.find(business_id) if business_id
        @org ||= Organization.find(org_id) if org_id
        @from_stafftools = args.fetch(:from_stafftools, false)
        @is_api_query = args.fetch(:is_api_query, false)
      end

      # Returns Search::Results or Driftwood::SearchResults if driftwood is enabled.
      def execute
        do_driftwood = from_stafftools ? query_driftwood_from_stafftools? : driftwood_queries_enabled?

        return original_query.execute unless do_driftwood

        res = driftwood_query.execute

        res.results.map! do |result|
          ::Audit::Elastic::Hit.new(result).tap do |hit|
            hit.after_initialize
            hit.nest_payload! unless @is_api_query
          end
        end

        res
      end

      def per_page=(num)
        @per_page = num
        if @original_query != nil
          @original_query.per_page = @per_page
        end
        @driftwood_query.per_page = @per_page
      end

      def self.new_org_business_query(es_query)
        from_graphql = es_query.delete(:from_graphql)
        from_api = es_query[:from_api]

        business = Business.find(es_query[:business_id]) if es_query[:business_id]
        org = Organization.find(es_query[:org_id]) if es_query[:org_id]
        user = es_query[:current_user]

        es_query[:feature_flags] = driftwood_feature_flags(
          query_flags: es_query[:feature_flags],
          check_sso_flag: true,
          user: user,
          org: org,
          business: business
        )
        es_query = org_business_options(es_query, business: business, org: org)

        enabled = driftwood_queries_enabled?

        # Log the orgs performing graphql queries to splunk
        GitHub.logger.info(
          "audit-log-query",
          "code.function" => "new_org_business_query",
          "gh.audit_log_query.from_graphql" => from_graphql,
          "gh.org.id" => org.try(:id),
          "gh.org.name" => org.try(:login),
          "gh.business.id" => business.try(:id),
          "gh.business.name" => business.try(:name),
        )

        if from_graphql
          enabled = driftwood_graphql_enabled?([user, org, business])

          GitHub.dogstats.increment("audit.org-business-query.graphql", { tags: ["destination:#{enabled ? "driftwood" : "legacyES"}"] })
        end

        return Search::Queries::AuditLogQuery.new(es_query.dup) unless enabled

        driftwood_query =
          case
          when es_query.key?(:org_id)
            build_org_query(T.must(org).id, es_query)
          when es_query.key?(:business_id)
            build_business_query(T.must(business).id, es_query)
          else
            raise "Missing org_id or business_id"
          end

        Audit::Driftwood::Query.new(es_query.merge(
          business: business,
          org: org,
          driftwood_query: driftwood_query,
          is_api_query: from_api,
        ))
      end

      def self.new_org_business_git_query(es_query)
        business = Business.find(es_query[:business_id]) if es_query[:business_id]
        org = Organization.find(es_query[:org_id]) if es_query[:org_id]
        user = es_query[:current_user]

        es_query[:feature_flags] = driftwood_feature_flags(
          query_flags: es_query[:feature_flags],
          check_sso_flag: true,
          user: user,
          org: org,
          business: business
        )
        es_query = org_business_options(es_query, business: business, org: org)

        enabled = driftwood_queries_enabled?

        unless enabled
          raise DriftwoodQueryNotPermitted.new("Queries to driftwood for git data not permitted for this user, org, and business")
        end

        driftwood_query =
          case
          when es_query.key?(:org_id)
            build_org_git_query(T.must(org).id, es_query.merge(from_api: true))
          when es_query.key?(:business_id)
            build_business_git_query(T.must(business).id, es_query.merge(from_api: true))
          else
            raise "Missing org_id or business_id"
          end

        Audit::Driftwood::Query.new(es_query.merge(
          business: business,
          org: org,
          original_query: nil,
          driftwood_query: driftwood_query,
          is_api_query: true,
        ))
      end

      def self.new_org_business_all_query(es_query)
        business = Business.find(es_query[:business_id]) if es_query[:business_id]
        org = Organization.find(es_query[:org_id]) if es_query[:org_id]
        user = es_query[:current_user]

        es_query[:feature_flags] = driftwood_feature_flags(
          query_flags: es_query[:feature_flags],
          check_sso_flag: true,
          user: user,
          org: org,
          business: business
        )
        es_query = org_business_options(es_query, business: business, org: org)

        unless driftwood_queries_enabled?
          raise DriftwoodQueryNotPermitted.new("Queries to driftwood for all data not permitted for this user, org, and business")
        end

        raise "Missing org_id or business_id" unless org || business

        driftwood_query = if org
          build_org_all_query(org.id, es_query.merge(from_api: true))
        else
          build_business_all_query(T.must(business).id, es_query.merge(from_api: true))
        end

        Audit::Driftwood::Query.new(es_query.merge(
          business: business,
          org: org,
          original_query: nil,
          driftwood_query: driftwood_query,
          is_api_query: true,
        ))
      end

      def self.new_project_query(options)
        project = options[:project]
        user = options[:current_user]
        org = nil
        org = project.owner if project.owner.is_a?(Organization)

        enabled = driftwood_queries_enabled?

        return Search::Queries::Audit::ProjectQuery.new(options) unless enabled

        latest_time = nil
        if options[:latest_allowed_entry_time].present?
          time = Time.parse(options[:latest_allowed_entry_time])
          latest_time = Google::Protobuf::Timestamp.new(seconds: time.to_i, nanos: time.nsec)
        end

        options[:feature_flags] = driftwood_feature_flags(query_flags: options[:feature_flags], user: user, org: org)
        driftwood_query = build_project_query(project, latest_time, options[:after], options[:feature_flags])

        Audit::Driftwood::Query.new(options.merge(
          org: org,
          driftwood_query: driftwood_query,
        ))

      end

      def self.new_user_query(options)
        user_id = options[:user_id] || options[:actor_id]
        user = options[:current_user] || User.find(user_id)

        enabled = driftwood_queries_enabled?

        if Rails.env.test?
          options = options.merge(index_name: GitHub.audit.searcher.generate_index)
        end

        return Search::Queries::AuditLogQuery.new(options) unless enabled

        options[:feature_flags] = driftwood_feature_flags(query_flags: options[:feature_flags], user: user)
        driftwood_query = build_user_query(options.merge(user_id: user_id, from_api: false))

        Audit::Driftwood::Query.new(options.merge(
          current_user: user,
          driftwood_query: driftwood_query,
        ))
      end

      def self.new_dormant_user_query(options)
        user_id = options[:actor_id]
        user = User.find(user_id)

        enabled = driftwood_queries_enabled?

        return Search::Queries::AuditLogQuery.new(options) unless enabled

        qparams = {
          user_id: user_id,
          feature_flags: driftwood_feature_flags(query_flags: options[:feature_flags], user: user),
          # We only use the first entry here, so only fetch one
          per_page: 1,
        }

        driftwood_query = driftwood_client.dormant_user_query(**qparams)

        Audit::Driftwood::Query.new(options.merge(
          current_user: user,
          driftwood_query: driftwood_query,
        ))
      end

      def self.new_2fa_user_query(options)
        user_id = options[:user_id] || options[:actor_id]
        user = User.find(user_id)

        enabled = driftwood_queries_enabled?

        original_options = options.merge(
          allowlist: ["user.two_factor_recovery_codes_downloaded", "user.two_factor_recovery_codes_printed", "user.two_factor_recovery_codes_viewed"],
        )

        original_options[:index_name] = GitHub.audit.searcher.generate_index if Rails.env.test?

        return Search::Queries::AuditLogQuery.new(original_options) unless enabled

        qparams = {
          user_id: user_id,
          feature_flags: driftwood_feature_flags(query_flags: options[:feature_flags], user: user),
          # We only use the first entry here, so only fetch one
          per_page: 1,
        }

        driftwood_query = driftwood_client.user_2fa_query(**qparams)

        Audit::Driftwood::Query.new(options.merge(
          current_user: user,
          driftwood_query: driftwood_query,
        ))
      end

      def self.new_stafftools_query(options)
        user = options[:current_user]
        enabled = query_driftwood_from_stafftools?

        original_options = options
        original_options[:per_page] ||= PER_PAGE
        original_options[:page] ||= 1

        return Search::Queries::StafftoolsQuery.new(original_options) unless enabled

        # remove `data.*` prefix for driftwood since we don't store it at the `data` level
        # modified_phrase = options[:phrase].gsub "data.feature_name", "feature_name"
        qparams = {
          phrase: options[:phrase],
          per_page: options.fetch(:per_page, PER_PAGE),
          after: options[:after],
          before: options[:before],
          feature_flags: driftwood_feature_flags(query_flags: options[:feature_flags], user: user),
        }

        driftwood_query = driftwood_stafftools_client.stafftools_query(**qparams)

        Audit::Driftwood::Query.new(options.merge(
          current_user: user,
          driftwood_query: driftwood_query,
          from_stafftools: true,
        ))
      end

      def self.org_dormancy(options)
        user = options[:current_user]
        enabled = driftwood_queries_enabled?

        original_options = options
        original_options[:per_page] ||= PER_PAGE
        original_options[:page] ||= 1

        return Search::Queries::StafftoolsQuery.new(original_options) unless enabled

        qparams = {
          phrase: options[:phrase],
          per_page: options.fetch(:per_page, PER_PAGE),
          after: options[:after],
          before: options[:before],
          feature_flags: driftwood_feature_flags(query_flags: options[:feature_flags], user: user),
        }

        driftwood_query = driftwood_client.stafftools_query(**qparams)

        Audit::Driftwood::Query.new(options.merge(
          current_user: user,
          driftwood_query: driftwood_query,
          from_stafftools: false,
        ))
      end

      def self.get_business_user_dormancy_latest_timestamp(options)
        if GitHub.single_business_environment?
          raise DriftwoodQueryNotPermitted.new(" business/user dormancy data not supported for single business environments")
        end

        user = options[:current_user]
        user_id = options[:user_id]
        business_id = options[:business_id]
        options[:feature_flags] = driftwood_feature_flags(query_flags: options[:feature_flags], user: user)

        driftwood_query = driftwood_client.dormant_business_user_query(user_id: user_id, business_id: business_id)

        q = Audit::Driftwood::Query.new(options.merge(
          current_user: user,
          driftwood_query: driftwood_query,
          from_stafftools: false,
        ))

        response = q.execute
        # It's possible that results will be in the shape of
        # [{"@timestamp" => nil}, {"@timestamp" => <Google::Protobuf::Timestamp>}]
        # where the "@timestamp" key is present but its value is nil.
        # we want the first entry with a non-nil value.
        response.results.filter_map { |r| r["@timestamp"].presence }.first&.to_time
      end

      def self.driftwood_queries_enabled?
        GitHub.driftwood_enabled?
      end

      def self.driftwood_graphql_enabled?(options = [])
        GitHub.driftwood_enabled?
      end

      def count
        @original_query.count
      end

      def self.driftwood_feature_flags(query_flags: [], check_sso_flag: false, user: nil, org: nil, business: nil)
        flags = []

        # include any flags passed into the query
        flags |= Array(query_flags)

        # include the show_sso_information flag if the business has the audit_sso_disclosure flag enabled
        if check_sso_flag
          target = business || org&.async_business&.sync
          if target.present? && GitHub.flipper[:audit_sso_disclosure].enabled?(target)
            flags |= ["show_sso_information"]
          end
        end

        # include flags enabled for the user, org, and business
        flags |= %w[driftwood_ade_query driftwood_cosmos_query_darkship driftwood_cosmos_query].select do |flag|
          [user, org, business].compact.any? { |subject| GitHub.flipper[flag].enabled?(subject) }
        end

        # Enable cosmos when no subject is passed and flag is globally enabled
        flags |= ["driftwood_cosmos_query"] if GitHub.flipper["driftwood_cosmos_query"].enabled? && user.nil? && org.nil? && business.nil?

        flags
      end

      def self.org_business_options(options, business: nil, org: nil)
        if !!business.try(:source_ip_disclosure_enabled?) || !!org.try(:source_ip_disclosure_enabled?)
          options[:disclose_ip_address] = true
        end

        if !!business.try(:enterprise_managed_user_enabled?)
          options[:is_emu_business] = true
        end

        options
      end

      # Internal: Configures the :page and :offset from the given options hash.
      # Only one value can be given otherwise an ArgumentError will be raised.
      #
      # opts - Options Hash
      #   :page   - One based page number
      #   :offset - Zero based offset into the search results
      #
      # Returns this Query instance.
      # Raises ArgumentError
      def configure_page_and_offset(opts)
        @original_query.configure_page_and_offset(opts)
        # There's no need to do this for the driftwood query since we use a cursor
        # but the `results` method in app/platform/connection_wrappers/driftwood_query.rb
        # will need to be changed once we switch over to driftwood

        self
      end

      def self.query_driftwood_from_stafftools?
        driftwood_queries_enabled? && !GitHub.enterprise?
      end

      private

      def driftwood_queries_enabled?
        self.class.driftwood_queries_enabled?
      end

      def driftwood_graphql_enabled?
        self.class.driftwood_graphql_enabled?([current_user, org, business])
      end

      def query_driftwood_from_stafftools?
        self.class.query_driftwood_from_stafftools?
      end

      def self.build_org_query(org_id, options)
        qparams = {
          org_id: org_id,
          phrase: options[:phrase],
          per_page: options.fetch(:per_page, PER_PAGE),
          region: "US",
          public_platform: options.fetch(:public_platform, false),
          direction: options.fetch(:direction, "DESC"),
          limit_history: options.fetch(:limit_history, false),
          after: options[:after],
          before: options[:before],
          api_request: options[:from_api],
          feature_flags: options[:feature_flags],
          disclose_ip_address: options[:disclose_ip_address],
        }

        driftwood_client.org_query(**qparams)
      end
      private_class_method :build_org_query

      def self.build_business_query(business_id, options)
        qparams = {
          business_id: business_id,
          phrase: options[:phrase],
          per_page: PER_PAGE,
          region: "US",
          after: options[:after],
          before: options[:before],
          api_request: options[:from_api],
          direction: options.fetch(:direction, "DESC"),
          feature_flags: options[:feature_flags],
          disclose_ip_address: options[:disclose_ip_address],
        }

        if options[:is_emu_business]
          driftwood_client.emu_query(**qparams)
        else
          driftwood_client.business_query(**qparams)
        end
      end
      private_class_method :build_business_query

      def self.build_org_git_query(org_id, options)
        qparams = {
          org_id: org_id,
          per_page: options.fetch(:per_page, PER_PAGE),
          region: "US",
          after: options[:after],
          before: options[:before],
          api_request: options[:from_api],
          direction: options.fetch(:direction, "DESC"),
          phrase: options[:phrase],
          feature_flags: options[:feature_flags],
          disclose_ip_address: options[:disclose_ip_address],
        }

        driftwood_client.org_git_query(**qparams)
      end
      private_class_method :build_org_git_query

      def self.build_business_git_query(business_id, options)
        qparams = {
          business_id: business_id,
          per_page: PER_PAGE,
          region: "US",
          after: options[:after],
          before: options[:before],
          api_request: options[:from_api],
          direction: options.fetch(:direction, "DESC"),
          phrase: options[:phrase],
          feature_flags: options[:feature_flags],
          disclose_ip_address: options[:disclose_ip_address],
        }

        if options[:is_emu_business]
          driftwood_client.emu_git_query(**qparams)
        else
          driftwood_client.business_git_query(**qparams)
        end
      end
      private_class_method :build_business_git_query

      def self.build_org_all_query(org_id, options)
        qparams = {
          org_id: org_id,
          per_page: options.fetch(:per_page, PER_PAGE),
          region: "US",
          after: options[:after],
          before: options[:before],
          phrase: options[:phrase],
          api_request: options[:from_api],
          direction: options.fetch(:direction, "DESC"),
          feature_flags: options[:feature_flags],
          disclose_ip_address: options[:disclose_ip_address],
        }

        driftwood_client.org_all_query(**qparams)
      end
      private_class_method :build_org_all_query

      def self.build_business_all_query(business_id, options)
        qparams = {
          business_id: business_id,
          per_page: PER_PAGE,
          region: "US",
          after: options[:after],
          before: options[:before],
          phrase: options[:phrase],
          api_request: options[:from_api],
          direction: options.fetch(:direction, "DESC"),
          feature_flags: options[:feature_flags],
          disclose_ip_address: options[:disclose_ip_address],
        }

        if options[:is_emu_business]
          driftwood_client.emu_all_query(**qparams)
        else
          driftwood_client.business_all_query(**qparams)
        end
      end
      private_class_method :build_business_all_query

      def self.build_project_query(project, latest_allowed_entry_time, after, feature_flags)
        qparams = {
          project_id: project.id,
          per_page: PER_PAGE,
          region: "US",
          latest_allowed_entry_time: latest_allowed_entry_time,
          after: after,
          feature_flags: feature_flags,
        }

        driftwood_client.project_query(**qparams)
      end
      private_class_method :build_project_query

      def self.build_user_query(options)
        qparams = {
          user_id: options[:user_id],
          per_page: options.fetch(:per_page, PER_PAGE),
          allowlist: options[:allowlist],
          phrase: options[:phrase],
          after: options[:after],
          before: options[:before],
          api_request: options[:from_api],
          feature_flags: options[:feature_flags],
          non_sso_org_ids: options[:non_sso_org_ids],
        }

        driftwood_client.user_query(**qparams)
      end

      private_class_method :build_user_query

      def self.driftwood_client
        GitHub.driftwood_client_v1
      end
      private_class_method :driftwood_client

      def self.driftwood_stafftools_client
        GitHub.driftwood_client_v1_stafftools
      end
      private_class_method :driftwood_stafftools_client

    end
  end
end
