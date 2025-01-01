# typed: true
# frozen_string_literal: true

module Search
  module Queries
    class AuditLogQuery < Search::Queries::Audit::Query
      # The amount of audit log indexes to query against.
      QUERY_INDEXES = 3

      # The amount of audit log indexes to query against with limited history set.
      LIMITED_HISTORY_INDEXES = 3

      # The set of fields that will be extracted from the query and turned into
      # filters.
      def self.field_list
        [
          :actor, :action, :user, :created, :country, :repo, :staff_actor, :operation, :ip, :hashed_token, :actor_ip, :org
        ].freeze
      end

      attr_reader :from
      attr_reader :to
      attr_reader :interval
      attr_reader :query_indexes
      attr_writer :raw

      # Construct an AuditLogQuery.
      #
      # options - The options Hash.
      #   :business_id   - The Business ID to filter by (optional).
      #   :org_id        - The Organization ID to filter by (optional).
      #   :user_id       - The User ID to filter by (optional).
      #   :actor_id      - The actor ID to filter by (optional).
      #   :allowlist     - The allowed actions are fetch by their prefix or
      #                    full action name (optional).
      #
      #                      Example:
      #
      #                        :allowlist => ["user.", "org.", "ssh.create"]
      #   :denylist     - The denylisted actions to exclude from the results
      #                    by their prefix or full action name (optional).
      #
      #                      Example:
      #
      #                        :denylist => ["user.unlock", "ssh."]
      #
      #
      #   :raw           - Whether or not the phrase should be parsed (optional).
      #   :index_name    - The specific index to query against (optional).
      #   :query_indexes - Builds the index name either staticly or
      #                    dynamically. (optional)
      #
      #                    You can query multiple months worth of audit log data
      #                    by providing how many months you want to query for as a
      #                    Integer. It will be relative to the current month.
      #
      #                      Example:
      #
      #                        :query_indexes => 3
      #                        # => audit_log-2014-06,audit_log-2014-05,audit_log-2014-04
      #
      #                    You can also query specific months of time by passing
      #                    Time objects directly. The year/month will be extracted
      #                    for you.
      #
      #                      Example:
      #
      #                        :query_indexes => [3.months.ago, 6.months.ago, 9.months.ago]
      #                        # => audit_log-2014-03,audit_log-2014-01,audit_log-2013-10
      #
      #   :interval      - The interval at which buckets will be created for each hit (default: day).
      #                    Valid options: year, quarter, month, week, day, hour, minute, second.
      #
      # Returns Search::Queries::AuditLogQuery instance.
      def initialize(options = {}, &block)
        if options[:blacklist]
          ActiveSupport.deprecator.warn("AuditLogQuery's blacklist argument has been renamed to denylist")
        end

        if options[:whitelist]
          ActiveSupport.deprecator.warn("AuditLogQuery's whitelist argument has been renamed to allowlist")
        end

        @business_id    = options.fetch(:business_id, nil)
        @org_id         = options.fetch(:org_id, nil)
        @user_id        = options.fetch(:user_id, nil)
        @actor_id       = options.fetch(:actor_id, nil)
        @staff_actor_id = options.fetch(:staff_actor_id, nil)
        @allowlist      = options.fetch(:allowlist, nil)
        @denylist       = options.fetch(:denylist, nil)
        @interval       = options.fetch(:interval, "hour")
        @search_type    = options.fetch(:search_type, nil)
        @query_indexes  = options.fetch(:query_indexes, QUERY_INDEXES).to_i
        @raw            = !!options.fetch(:raw, false)
        @direction      = options.delete(:direction).to_s.upcase == "ASC" ? :asc : :desc
        @index_name     = options.delete(:index_name)
        @limit_history  = !!options.fetch(:limit_history, false)
        @from_api       = options.delete(:from_api)
        @events_type    = options.delete(:events_type) || :web

        super(options, &block)

        if subject = options.delete(:subject)
          parse_subject(subject)
        end

        # If we didn't find a date in the original phrase set the default range
        if @created_filter.nil?
          parse_range
        end
      end

      def phrase=(value)
        super(value)
        parse_range
      end

      # Internal: To query against a smaller subset of audit log indexes
      # override index path the query queries against.
      #
      # Returns Hash.
      def query_params
        index = build_index_name
        instrument_query_indices(index)
        params = {
          index: index,
          type: "audit_entry",
          ignore_unavailable: true,
        }
        # COMPATIBILITY - once we're on ES5, convert this ES2 workaround to explicit _count query
        if count_query?
          params[:size] = 0
        end
        params
      end

      # COMPATIBILITY - once we're on ES5, let's convert to explicit _count queries
      def count_query?
        @search_type == "count"
      end

      # TODO: break out a new prefix field for each action to avoid high action cardinality in filters below
      def allowlist
        @allowlist ||=
          if business?
            business_list =
              if GitHub.single_business_environment?
                AuditLogEntry.business_server_action_names | AuditLogEntry.user_action_names
              else
                AuditLogEntry.business_cloud_action_names
              end
            business_list |= AuditLogEntry.business_api_only_action_names if from_api?
            business_list &= git_event_list if only_git_events?
            business_list
          elsif organization?
            org_list = AuditLogEntry.organization_action_names
            org_list |= AuditLogEntry.organization_api_only_action_names if from_api?
            org_list &= git_event_list if only_git_events?
            org_list
          elsif GitHub.instance_audit_log_enabled? && !user?
            business_list = AuditLogEntry.business_server_action_names | AuditLogEntry.user_action_names
            business_list |= AuditLogEntry.business_api_only_action_names if from_api?
            business_list &= git_event_list if only_git_events?
            business_list
          else
            AuditLogEntry.user_action_names
          end
      end

      def only_git_events?
        GitHub.single_business_environment? && @events_type == :git
      end

      def git_event_list
        [
          "git.fetch",
          "git.clone",
          "git.push",
        ]
      end

      def allowlist_prefixes
        @allowlist_prefixes ||= allowlist.map { |action| action.split(".").first }.uniq
      end

      def allowlist_and_prefixes
        allowlist + allowlist_prefixes
      end

      def denylist
        @denylist ||= []
        if GitHub.single_business_environment? && @events_type == :web
          @denylist |= git_event_list
        end

        @denylist
      end

      def aggregation_fields
        # note: @timestamp aggregation is quantized in ES query to day, hour etc.
        if count_query?
          [:@timestamp]
        else
          ["actor_location.country_code", :@timestamp]
        end
      end

      def raw?
        !!@raw
      end

      # Public: Determine if the query is for a business.
      #
      # Returns true if business is present, otherwise false.
      def business?
        @business_id.present?
      end

      # Public: Determine if the query is for an organization.
      #
      # Returns true if org is present, false if not.
      def organization?
        @org_id.present?
      end

      # Public: Determine if the query is for a user.
      #
      # Returns true if user or actor is present, false if not.
      def user?
        @user_id.present? || @actor_id.present?
      end

      # Public: Can the current user query the audit log by IP?
      #
      # Returns Boolean.
      def can_query_by_ip?
        same_user? || business_query_with_ip_disclosure_enabled?
      end

      sig do
        override
        .params(skip_prune_results: T::Boolean, results_class: T.class_of(Search::Results))
        .returns(Search::Results[T.untyped])
      end
      def execute(skip_prune_results: false, results_class: Search::Results)
        results = super

        if valid_query?
          index_length = @index_name.split(",").length
          GitHub.dogstats.distribution("search.query.index_count", index_length, tags: ["index:#{index.name}"])
          # Keep track of the total number of results that matched the query.
          # Metrics are split on the presence of a user query or default query.
          if organization? && !count_query?
            if phrase.present?
              GitHub.dogstats.distribution("audit.results.orgs.query.total", results.total)
            else
              GitHub.dogstats.distribution("audit.results.orgs.default.total", results.total)
            end
          end
        end

        results
      rescue StandardError => boom # rubocop:todo Lint/GenericRescue
        Failbot.report(boom, fatal: "NO")
        Search::Results.empty
      end

      # Prevents a double filter from being applied since we want to include
      # aggregation fields in the main +build_query_filter+ method.
      def build_filter
      end

      def build_query_filter
        filter = Search::Filters::BoolFilter.new(filter_hash)
        query_filter = filter.build

        if query_filter[:bool][:should]
          query_filter[:bool][:minimum_should_match] = 1
        end

        query_filter
      end

      def filter_hash
        return @filter_hash if defined? @filter_hash

        reshape_country_qualifiers

        filters = {}

        # should filters
        qualifiers[:user_id].clear.should(@user_id)
        filters[:user_id] = builder.term_filter(:user_id)

        qualifiers[:actor_id].clear.should(@actor_id)
        filters[:actor_id] = builder.term_filter(:actor_id)

        qualifiers[:business_id].clear.should(@business_id)
        filters[:business_id] = builder.term_filter(:business_id)

        qualifiers[:org_id].clear.should(@org_id)
        filters[:org_id] = builder.term_filter(:org_id)

        # must filters
        filters[:actor]                        = builder.term_filter(:actor, execution: :or)
        filters[:user]                         = builder.term_filter(:user, execution: :or)
        filters[:repo]                         = builder.term_filter(:repo, execution: :or)
        filters[:org]                          = builder.term_filter(:org, execution: :or)
        filters[:staff_actor]                  = builder.term_filter(:staff_actor, execution: :or)
        filters[:staff_actor_id]               = builder.term_filter(:staff_actor_id)
        filters[:operation_type]               = builder.term_filter(:operation_type, :operation, execution: :or)
        filters["data.hashed_token"]           = build_hashed_token_filter
        filters["actor_location.country_code"] = builder.term_filter("actor_location.country_code", :country_code, execution: :or)
        filters["actor_location.country_name"] = builder.term_filter("actor_location.country_name", :country_name, execution: :or)
        filters["data._invalid"]               = build_invalid_filter
        filters[:created]                      = build_created_filter
        filters[:action]                       = build_action_filter

        if can_query_by_ip?
          filters[:actor_ip] = builder.term_filter(:actor_ip, :ip, execution: :or)
        end

        # remove empties from the filter list now that it's populated
        filters.delete_if { |_name, filter| filter.nil? || (filter.valid? && filter.blank?) }
        @filter_hash = filters
      end

      def build_aggregations
      end

      def build_sort
        {
          :@timestamp => {
            order: @direction,
          },
        }
      end

      def from_api?
        !!@from_api
      end

      private

      # Private: Determines if the user querying the Audit Log is the same user
      # as the Audit Log they're trying to query.
      #
      # Returns true if user is same as actor, false if not.
      def same_user?
        return false unless @actor_id.present?
        return false unless current_user.present?

        @actor_id == current_user.id
      end

      # Private: Is this a query for a Business where source IP disclosure is enabled?
      #
      # Returns Boolean.
      def business_query_with_ip_disclosure_enabled?
        return false unless business?
        return false unless business = Business.find_by(id: @business_id)

        business.can_enable_audit_log_ip_disclosure? && business.source_ip_disclosure_enabled?
      end

      # Private: Given the list of indices to query, keep track of how many times
      # we query each index. This is helpful to keep track of the indices
      # Search::Queries::AuditLogQuery is querying most often.
      #
      # Returns nothing.
      def instrument_query_indices(indices)
        indices.split(",").each do |index|
          GitHub.dogstats.increment("audit.query.index", { tags: ["index:" + index.to_s] })
        end
      end

      # Private:  Splits the qualifiers into 2 groups, one for country codes and
      # one for country names to allow for flexible country searching.
      #
      # Returns nothing.
      def reshape_country_qualifiers
        qualifiers[:country_name].clear
        qualifiers[:country_code].clear

        if qualifiers[:country].must?
          country_codes_must, country_names_must = qualifiers[:country].must.partition do |country|
            country.length == 2
          end

          qualifiers[:country_code].must(country_codes_must.map(&:upcase))
          qualifiers[:country_name].must(country_names_must)
        end

        if qualifiers[:country].must_not?
          country_codes_must_not, country_names_must_not = qualifiers[:country].must_not.partition do |country|
            country.length == 2
          end

          qualifiers[:country_code].must_not(country_codes_must_not.map(&:upcase))
          qualifiers[:country_name].must_not(country_names_must_not)
        end

        qualifiers[:country].clear
      end

      # Private: Builds the action type filter. Given a allowlist, a denylist, and a
      # phrase (which populates qualifiers[:action]). A final allowlist is derived to use
      # for filtering the query to a specific action or set of actions.
      def build_action_filter
        must = qualifiers[:action].must || []
        must_not = qualifiers[:action].must_not || []

        # Negated action prefix terms i.e. -action:user
        must_not_prefixes = allowlist_prefixes & must_not

        # Negated action terms i.e. action:user.create
        must_not_actions = must_not - must_not_prefixes

        expanded_must_not_actions = denylist | must_not_actions | must_not_prefixes.flat_map do |prefix|
          ::Audit::ALL_ACTIONS.select { |action| action.start_with?(prefix) }
        end

        # Action prefix terms i.e. action:user
        must_prefixes = allowlist_prefixes & must

        # Action terms i.e. action:user.create
        must_actions  = must - must_prefixes

        expanded_must_actions = must_actions | must_prefixes.flat_map do |prefix|
          allowlist.select { |action| action.start_with?(prefix) }
        end

        final_allowlist =
          if expanded_must_actions.any?
            (allowlist & expanded_must_actions) - expanded_must_not_actions
          else
            allowlist - expanded_must_not_actions
          end

        qualifiers[:action].clear
        qualifiers[:action].must(final_allowlist)

        builder.action_filter(:action, execution: :or, denylist: expanded_must_not_actions)
      end

      def build_invalid_filter
        qualifiers["data._invalid"].clear
        qualifiers["data._invalid"].must_not(true)

        filter = Search::Filters::TermFilter.new \
          field: "data._invalid",
          qualifiers: qualifiers
        filter.map_bool_collection
        filter
      end

      def build_hashed_token_filter
        val = qualifiers[:hashed_token].must

        qualifiers.delete(:hashed_token)
        qualifiers["data.hashed_token"].clear

        return unless val.present? && val.length > 0
        qualifiers["data.hashed_token"].must(val)

        filter = Search::Filters::TermFilter.new \
          field: "data.hashed_token",
          qualifiers: qualifiers
        filter.map_bool_collection
        filter
      end

      # Private: If a subject is provided to the query it will try to be smart
      # about the context for the query.
      #
      # subject - User, Organization, or Business instance.
      #
      # Returns nothing.
      def parse_subject(subject)
        case subject
        when Business
          @business_id ||= subject.id
        when Organization
          @org_id ||= subject.id
        when User
          @actor_id ||= subject.id
        else
          raise ArgumentError, "Invalid subject, expected User, Organization, or Business"
        end
      end

      # Private: Takes the from and to attributes from the parsed query to
      # scope the results to fetch.
      #
      # Returns nothing.
      def parse_range
        return if raw?

        @from = nil
        @to = nil
        @created_filter = nil

        if qualifiers[:created].must?
          build_created_filter
        else
          build_default_created_filter
        end

        @created_filter
      end

      # Private: Builds the timestamp filter used to filter audit log
      # entries. All timestamps are extracted and converted to UTC then
      # re-built.
      #
      # Returns Search::Filters::DateRangeFilter
      def build_created_filter
        @created_filter ||= begin
          return if raw?

          # Parse the user supplied qualifier
          user_filter = Search::Filters::DateRangeFilter.new \
            field: :@timestamp,
            keys: :created,
            qualifiers: qualifiers
          user_filter.map_bool_collection
          return user_filter if !user_filter.valid? || user_filter.must.nil?

          # Collect all possible ranges. Possible there is more than one. Last
          # one will always supercede the previous filter in the case of gt,
          # gte, lt, or lte.
          ranges = if user_filter.must.key?(:bool)
            user_filter.must[:bool][:should].collect do |filter|
              filter[:range][:@timestamp]
            end
          else
            Array.wrap(user_filter.must.dig(:range, :@timestamp))
          end

          # if ranges is empty then we couldn't pass ranges and we should just return early
          return user_filter if ranges.empty?

          # Each range filter has a key storing the time range in gt, gte, lt,
          # and lte.
          range = {}
          ranges.each do |el|
            els = el.slice(:gt, :gte, :lt, :lte)
            range.merge!(els)
          end

          @from, @to = parse_ranges(range)

          build_index_name

          # If user queries for just a single day, we need to make sure the `from`
          # and `to` dates range the full day taking into account the user's time zone.
          if @from == @to
            @to = @to.in_time_zone.end_of_day
          end

          set_created_filter(from: @from, to: @to)
        end
      end

      # Private: Builds the default timestamp filter used to filter audit logs.
      # The default filter is from query_indexes number of months go to now.
      #
      # Returns Search::Filters::DateRangeFilter
      def build_default_created_filter
        @to = Time.zone.now.end_of_day
        @from = (@to - query_indexes.months).beginning_of_day.utc
        @to = @to.utc
        set_created_filter(from: @from, to: @to)
      end

      def set_created_filter(from:, to:)
        qualifiers[:created].clear.must("#{from.iso8601(3)}..#{to.iso8601(3)}")

        @created_filter = Search::Filters::DateRangeFilter.new(
          field: :@timestamp,
          keys: :created,
          qualifiers: qualifiers,
        )

        @created_filter.map_bool_collection
        @created_filter
      end

      # Internal: Removes Elasticsearch date rounding from date/time strings
      # Returns a cleaned up date/time string
      def cleanup_date_time(str)
        str.sub(/\|\|\/[yMdh]\Z/, "")
      end

      # Private: Builds the index name used to query audit log events based on
      # many aggregations. It considers if it's a raw query, raw index name provided,
      # or user provided date range. If the limit_history option is
      # set than the oldest possible index that can be queried will be from now
      # to LIMITED_HISTORY_INDEXES months ago.
      #
      # Returns String.
      def build_index_name
        return @index_name if @index_name

        range = if raw?
          :all
        elsif @from && @to
          # Don't query for entries in the future
          max = [@to.localtime, Time.now].min.utc
          min = [@from.localtime, Time.now].min.utc

          if @limit_history
            limit = T.cast((Time.now - LIMITED_HISTORY_INDEXES.months), Time).beginning_of_day.utc
            min = [min, limit].max.utc
            max = [max, limit].max.utc
          end

          month_range(min, max)
        end

        @index_name = GitHub.audit.searcher.generate_index(range)
      end

      # Private: Builds range of months the start and stop span accross.
      #
      # start - The Time to seek from.
      # stop  - The Time to seek to.
      #
      # Returns Array of DateTime instances.
      def month_range(start, stop)
        months = []
        stop.to_date.downto(start.to_date) do |day|
          months << DateTime.civil(day.year, day.month)
        end
        months.uniq
      end

      def detect_in_utc(value)
        # if the range contains an ISO8061 formatted string with `Z`, then don't convert to utc
        # this is already considered to be in UTC
        value.end_with?("Z")
      end

      def parse_ranges(range)
        from_in_utc = false
        to_in_utc = false

        to = if range[:lte]
          to_in_utc = detect_in_utc(range[:lte])
          lte = cleanup_date_time(range[:lte])
          end_of_date(lte, parse_date(lte))
        elsif range[:lt]
          to_in_utc = detect_in_utc(range[:lt])
          lt = cleanup_date_time(range[:lt])
          # We want to subtract a single time unit here
          # so that when we pass our range to DateRangeFilter it excludes this value
          ltd = subtract_time(lt, parse_date(lt))
          end_of_date(lt, ltd)
        else
          Time.zone.now.end_of_day
        end

        from = if range[:gte]
          from_in_utc = detect_in_utc(range[:gte])
          gte = cleanup_date_time(range[:gte])
          beginning_of_date(gte, parse_date(gte))
        elsif range[:gt]
          from_in_utc = detect_in_utc(range[:gt])
          gt = cleanup_date_time(range[:gt])
          # We want to add a single time unit here
          # so that when we pass our range to DateRangeFilter it excludes this value
          gtd = add_time(gt, parse_date(gt))
          beginning_of_date(gt, gtd)
        else
          (to - query_indexes.months).beginning_of_day
        end

        [
          from_in_utc ? from : Time.zone.local_to_utc(from),
          to_in_utc ? to : Time.zone.local_to_utc(to),
        ]
      end

      def end_of_date(input, date)
        case input.length
        when 4;  date.end_of_year
        when 7;  date.end_of_month
        when 10; date.end_of_day
        when 13; date.end_of_hour
        when 16; date + 1.minute - 1.second
        else     date
        end
      end

      def beginning_of_date(input, date)
        case input.length
        when 4;  date.beginning_of_year
        when 7;  date.beginning_of_month
        when 10; date.beginning_of_day
        when 13; date.at_beginning_of_hour
        when 16; date.at_beginning_of_minute
        else     date
        end
      end

      def parse_date(value)
        case value.length
        when 4;  Time.strptime(value, "%Y")
        when 7;  Time.strptime(value, "%Y-%m")
        when 10; Time.strptime(value, "%Y-%m-%d")
        when 13; Time.strptime(value, "%Y-%m-%dT%H")
        when 16; Time.strptime(value, "%Y-%m-%dT%H:%M")
        when 19; Time.strptime(value, "%Y-%m-%dT%H:%M:%S")
        else     Time.zone.parse(value).utc
        end
      end

      def add_time(input, t)
        t + calc_date_math_based_on_precision(input)
      end

      def subtract_time(input, t)
        t - calc_date_math_based_on_precision(input, :sub)
      end

      def calc_date_math_based_on_precision(value, operation = nil)
        case value.length
        when 4;       1.year   #YYYY
        when 7;       1.month  #YYYY-MM
        when 10;      1.day    #YYYY-MM-DD
        when 13;      1.hour   #YYYY-MM-DDTHH
        when 16, 17;  1.minute #YYYY-MM-DDTHH:MM or YYYY-MM-DDTHH:MMZ
        when 19, 20;  1.second #YYYY-MM-DDTHH:MM:SS or YYYY-MM-DDTHH:MM:SSZ
        else
          # We need to check the operation since subtracting 0.001.seconds doesn't actually subtract
          # 1ms, it subtracts 2ms (or 1.999999ms rounded) not sure why, but it is what it is
          if operation == :sub
            1 / 1001.0
          else
            0.001.seconds
          end
        end
      end
    end
  end
end
