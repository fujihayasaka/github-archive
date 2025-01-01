# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    module React
      class IndexPayloadBuilder < BasePayloadBuilder
        include SecretScanning::Features::FeatureFlagHelper
        QUERY_PARSER = Search::Queries::SecurityCenter::SecretScanningQuery

        sig do
          params(
            alerts: T::Array[GitHub::TokenScanning::Service::Token],
            open_alert_count: Integer,
            closed_alert_count: Integer,
            query_string: String,
            page_size: Integer,
            page: T.nilable(Integer),
            has_pending_backfill: T::Boolean,
            has_backfill_scanning_terminal_error: T::Boolean,
            has_backfill_scan_max_candidates: T::Boolean,
          ).returns(T::Hash[T.untyped, T.untyped])
        end
        def page_payload(
            alerts,
            open_alert_count,
            closed_alert_count,
            query_string,
            page_size,
            page,
            has_pending_backfill,
            has_backfill_scanning_terminal_error,
            has_backfill_scan_max_candidates
          )

          query_parser = QUERY_PARSER.new(query: query_string)

          owner_type = if @repo.owner&.user?
            "USER"
          elsif @repo.owner&.organization?
            "ORGANIZATION"
          else
            "UNKNOWN"
          end

          issues = get_issues_for_alerts(alerts) #retrieve all issues based on first location id
          organization = @repo.owner if @repo.owner&.organization?

          delegated_alert_closures_feature = SecretScanning::Features::Repo::DelegatedClosures.new(@repo)
          {
            alerts: alerts.map do |alert|
              result = serialize_alert(alert)
              result.first_location_description = get_first_location_description(alert, issues)
              result.serialize
            end,
            plaid_ui_filters_enabled: @user.feature_flag_enabled?(FeatureFlags::PLAID_UI_FILTERS, default: true),
            open_alert_count: open_alert_count,
            closed_alert_count: closed_alert_count,
            page: page,
            total_pages: get_total_pages(open_alert_count, closed_alert_count, query_string, page_size),
            repository: {
              name: @repo.name,
              owner_display_login: @repo.owner_display_login,
              owner_type: owner_type,
            },
            backfill_status: backfill_status(has_pending_backfill, has_backfill_scanning_terminal_error, has_backfill_scan_max_candidates).serialize,
            show_user_feedback_link: show_user_feedback_link?,
            show_results_category: show_results_category?,
            user_feedback_notice: UserNotice::SECRET_SCANNING_FEEDBACK_NOTICE,
            query: {
              query_string: query_string,
              url: QUERY_PARSER.query_string_for_url(query_string)[1..-1], # [1..-1] is to remove the leading `?` from the query string
              filters_applied: filters_applied?(query_string),
              is_open: query_parser.is_open_page?,
              is_open_query: query_parser.get_is_state_query_string(QUERY_PARSER::IS_OPEN),
              is_closed: query_parser.is_closed_page?,
              is_closed_query: query_parser.get_is_state_query_string(QUERY_PARSER::IS_CLOSED),
              default: query_string == "is:open",
              default_query: "is:open",
              sort_options: generate_sort_options(query_string),
              resolution_clear_all: resolution_clear_all(query_string),
              resolution_options: generate_resolution_options(@repo, query_string),
              results_category_options: generate_results_category_options(@repo, query_string),
              secret_type_clear_all: secret_type_clear_all(query_string),
              provider_clear_all: provider_clear_all(query_string),
              validity_clear_all: validity_clear_all(query_string),
              validity_options: generate_validity_options(@repo, query_string),
              bypassed_clear_all: bypassed_clear_all(query_string),
              bypassed_options: generate_bypassed_options(@repo, query_string),
              assignee_clear_all: assignee_clear_all(query_string),
              assignee_options: generate_assignee_options(query_string),
              valid: query_parser.is_valid?,
              campaign_clear_all: campaign_clear_all(query_string),
              campaign_options: generate_campaign_options(@repo, query_string),
            },
            resolve_alerts_allowed: SecretScanning::Features::Repo::TokenScanning.new(@repo).resolve_alerts_allowed?(@user, []),
            delegated_closures_enabled: delegated_alert_closures_feature.enabled?,
            alert_assignees_enabled: feature_flag_enabled_in_hierarchy?(@repo, FeatureFlags::SECRET_SCANNING_ALERT_ASSIGNEE),
            self_serve_banner: SecretScanning::Util::SelfServeBanner.banner_properties(@user, SecretScanning::Constants::SelfServeBannerSlugs::SECRET_PROTECTION_FEEDBACK_SURVEY),
            show_campaign_filter: FeatureFlag.vexi.enabled?(:secret_scanning_campaigns, @user, organization, organization&.business, default: false)
          }
        end

        sig do
          params(
            query_string: String,
            option_collections: T::Array[T::Hash[Symbol, T::Array[T::Hash[Symbol, T.any(String, Integer)]]]]
          ).returns(T::Array[T::Hash[Symbol, T.any(String, T::Boolean)]])
        end
        def filter_secret_type_options_payload(query_string, option_collections)
          query_parser = QUERY_PARSER.new(query: query_string)

          option_collections.select { |option_collection| option_collection[:items].present? }.flat_map do |option_collection|
            T.must(option_collection[:items]).map do |option| # we already filtered to only have collections with items
              excluded = secret_type_option_excluded?(query_string, T.must(option[:slug]).to_s)
              {
                label: option[:label],
                slug: option[:slug],
                query: secret_type_option_query(query_string, T.must(option[:slug]).to_s, excluded),
                checked: secret_type_option_checked?(query_string, T.must(option[:slug]).to_s),
                excluded: excluded,
                count: option[:count],
                category: option_collection[:title],
              }
            end
          end
        end


        sig do
          params(
            query_string: String,
            option_collections: T::Array[T::Hash[Symbol, T::Array[T::Hash[Symbol, T.any(String, Integer)]]]]
          ).returns(T::Array[T::Hash[Symbol, T.any(String, T::Boolean)]])
        end
        def filter_provider_options_payload(query_string, option_collections)
          query_parser = QUERY_PARSER.new(query: query_string)

          option_collections.select { |option_collection| option_collection[:items].present? }.flat_map do |option_collection|
            T.must(option_collection[:items]).map do |option| # we already filtered to only have collections with items
              excluded = provider_option_excluded?(query_string, T.must(option[:slug]).to_s)
              {
                label: option[:label],
                slug: option[:slug],
                query: provider_option_query(query_string, T.must(option[:slug]).to_s, excluded),
                checked: provider_option_checked?(query_string, T.must(option[:slug]).to_s),
                excluded: excluded,
                count: option[:count],
                category: option_collection[:title],
              }
            end
          end
        end

        sig { params(query_string: String).returns(T::Hash[Symbol, T.any(String, T::Boolean)]) }
        def assignee_clear_all(query_string)
          {
            label: "Clear assignees",
            slug: nil,
            query: SecurityCenter::SelectMenuComponentHelper.query_clear_all(
              qualifiers: [QUERY_PARSER::QUALIFIER_ASSIGNEE, QUERY_PARSER::QUALIFIER_HAS, QUERY_PARSER::QUALIFIER_NO],
              query: query_string,
              query_parser: QUERY_PARSER),
            checked: false,
            excluded: false,
            hidden: !has_assignee_filters?(query_string)
          }
        end

        sig { params(query_string: String).returns(T::Array[T::Hash[Symbol, T.any(String, T::Boolean)]]) }
        def generate_assignee_options(query_string)
          assignee_option_query = SecurityCenter::SelectMenuComponentHelper.query_string(
              is_multiselect: false,
              qualifier_to_select: QUERY_PARSER::QUALIFIER_ASSIGNEE,
              qualifiers_to_remove: [QUERY_PARSER::QUALIFIER_ASSIGNEE, QUERY_PARSER.negate_qualifier(QUERY_PARSER::QUALIFIER_ASSIGNEE), QUERY_PARSER::QUALIFIER_HAS, QUERY_PARSER::QUALIFIER_NO],
              query: query_string,
              query_parser: QUERY_PARSER,
              slug: "@me")

          assignee_option_checked = QUERY_PARSER.get_qualified_values(query_string, QUERY_PARSER::QUALIFIER_ASSIGNEE).include?("@me")
          [
            # Filtering by self
            {
              label: "Me",
              slug: "@me",
              query: assignee_option_query,
              checked: assignee_option_checked,
              excluded: false,
            },
          ]
        end

        private

        sig { params(query_string: String).returns(T::Boolean) }
        def has_assignee_filters?(query_string)
          QUERY_PARSER.get_qualified_values(query_string, QUERY_PARSER::QUALIFIER_ASSIGNEE).any? ||
          QUERY_PARSER.get_qualified_values(query_string, QUERY_PARSER.negate_qualifier(QUERY_PARSER::QUALIFIER_ASSIGNEE)).any? ||
          QUERY_PARSER.get_qualified_values(query_string, QUERY_PARSER::QUALIFIER_HAS).include?("assignee") ||
          QUERY_PARSER.get_qualified_values(query_string, QUERY_PARSER::QUALIFIER_NO).include?("assignee")
        end

        sig do
          params(
            has_pending_backfill: T::Boolean,
            has_backfill_scanning_terminal_error: T::Boolean,
            has_backfill_scan_max_candidates: T::Boolean,
          ).returns(SecretScanning::Models::React::BackfillStatusType)
        end
        def backfill_status(has_pending_backfill, has_backfill_scanning_terminal_error, has_backfill_scan_max_candidates)
          return SecretScanning::Models::React::BackfillStatusType::Pending if has_pending_backfill
          return SecretScanning::Models::React::BackfillStatusType::TerminalError if has_backfill_scanning_terminal_error
          return SecretScanning::Models::React::BackfillStatusType::MaxCandidates if has_backfill_scan_max_candidates
          SecretScanning::Models::React::BackfillStatusType::None
        end

        sig { params(open_alert_count: Integer, closed_alert_count: Integer, query: String, page_size: Integer).returns(Integer) }
        def get_total_pages(open_alert_count, closed_alert_count, query, page_size)
          selected_token_state = QUERY_PARSER.get_qualified_values(query, QUERY_PARSER::QUALIFIER_IS).first

          if selected_token_state == QUERY_PARSER::IS_OPEN
            total_tokens = open_alert_count
          elsif selected_token_state == QUERY_PARSER::IS_CLOSED
            total_tokens = closed_alert_count
          else
            total_tokens = open_alert_count + closed_alert_count
          end

          return 1 if total_tokens.zero?
          (total_tokens.to_f / page_size).ceil
        end

        sig { params(alerts: T::Array[GitHub::TokenScanning::Service::Token]).returns(T::Hash[Integer, Issue]) }
        def get_issues_for_alerts(alerts)
          ActiveRecord::Base.connected_to(role: :reading) do
            @repo.issues.where(
              id: alerts.map(&:first_location)
                        .compact
                        .select { |location| [:ISSUE_TITLE, :ISSUE_BODY, :ISSUE_COMMENT].include?(location.content_type) }
                        .map(&:content_id)
            ).index_by(&:id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          end
        end

        sig { params(alert: GitHub::TokenScanning::Service::Token, issues: T::Hash[Integer, Issue]).returns(T.nilable(String)) }
        def get_first_location_description(alert, issues)
          return "Secret is no longer present in git history" if !alert.raw_secret_in_git_history?
          return nil if alert.first_location.nil?

          secret_classification = alert.is_custom? ? "custom pattern" : "secret"

          location = nil
          case alert.first_location.content_type
          when :REPOSITORY_BLOB, :WIKI_BLOB
            location = ""
            location += "GitHub wiki page " if alert.first_location.content_type == :WIKI_BLOB

            location += reverse_truncate_path(
                alert.first_location.path,
                FILE_PATH_TRUNCATION_LENGTH
              )

            location += ":#{alert.first_location.start_line}" unless alert.found_in_archive?
          when :ISSUE_TITLE, :ISSUE_BODY, :ISSUE_COMMENT
            issue = issues[alert.first_location.content_id]
            if issue.present? && issue.pull_request_id.present?
              location = "pull request ##{alert.first_location.content_number}"
            else
              location = "issue ##{alert.first_location.content_number}"
            end
          when :DISCUSSION_TITLE, :DISCUSSION_BODY, :DISCUSSION_COMMENT
            location = "discussion ##{alert.first_location.content_number}"
          when :PULL_REQUEST_TITLE, :PULL_REQUEST_BODY, :PULL_REQUEST_COMMENT,  :PULL_REQUEST_REVIEW, :PULL_REQUEST_REVIEW_COMMENT, :PULL_REQUEST_TIMELINE_COMMENT
            location = "pull request ##{alert.first_location.content_number}"
          end

          return nil if location.nil?
          "Detected #{secret_classification} in #{location}"
        end

        # Takes a directory such as `root/first_dir/middle_dir/last_dir/file.ext` and truncates to `root/.../last_dir/file.ext`
        # Additionally, truncates each path segment to max_segment_length plus `...`
        sig { params(path: String, max_segment_length: Integer).returns(String) }
        def reverse_truncate_path(path, max_segment_length)
          directory_levels = path.split("/")

          directory_levels.map! do |level|
            next T.must(level[0, max_segment_length]) + "..." if level.length > max_segment_length
            level
          end

          return T.must(directory_levels[0]) + "/.../" + T.must(directory_levels[-2]) + "/" + T.must(directory_levels[-1]) if directory_levels.length > 3
          directory_levels.join("/")
        end

        sig { params(query_string: String).returns(T::Boolean) }
        def filters_applied?(query_string)
          sortion_options_removed = QUERY_PARSER.remove_qualifier(query_string, QUERY_PARSER::QUALIFIER_SORT)
          sortion_options_removed != "is:open"
        end

        sig { params(query_string: String).returns(T::Array[T::Hash[Symbol, T.any(String, T::Boolean)]]) }
        def generate_sort_options(query_string)
          QUERY_PARSER.sort_options.map do |sort_option|
            {
              label: sort_option[:label],
              slug: sort_option[:slug],
              query: sort_option_query(query_string, sort_option[:slug]),
              checked: sort_option_checked?(query_string, sort_option[:slug]),
              excluded: false
            }
          end
        end

        sig { params(query_string: String, sort_slug: String).returns(String) }
        def sort_option_query(query_string, sort_slug)
          SecurityCenter::SelectMenuComponentHelper.query_string(
            is_multiselect: false,
            qualifier_to_select: QUERY_PARSER::QUALIFIER_SORT,
            qualifiers_to_remove: [QUERY_PARSER::QUALIFIER_SORT],
            query: query_string,
            query_parser: QUERY_PARSER,
            slug: sort_slug)
        end

        sig { params(query_string: String, sort_slug: String).returns(T::Boolean) }
        def sort_option_checked?(query_string, sort_slug)
          SecurityCenter::SelectMenuComponentHelper.checked?(
            default_selected_slug: QUERY_PARSER::DEFAULT_SORT_SLUG_VALUE,
            qualifier: QUERY_PARSER::QUALIFIER_SORT,
            query: query_string,
            query_parser: QUERY_PARSER,
            slug: sort_slug,
            use_default_selected_slug_on_invalid_values: false,
            valid_values: QUERY_PARSER.sort_options.map { |option| option[:slug] })
        end


        sig { params(query_string: String).returns(T::Hash[Symbol, T.any(String, T::Boolean)]) }
        def resolution_clear_all(query_string)
          {
            label: "Clear closure reasons",
            slug: nil,
            query: SecurityCenter::SelectMenuComponentHelper.query_clear_all(
              qualifiers: [QUERY_PARSER::QUALIFIER_RESOLUTION],
              query: query_string,
              query_parser: QUERY_PARSER),
            checked: false,
            excluded: false,
            hidden: !QUERY_PARSER.get_qualified_values(query_string, QUERY_PARSER::QUALIFIER_RESOLUTION).any?
          }
        end

        sig { params(repo: Repository, query_string: String).returns(T::Array[T::Hash[Symbol, T.any(String, T::Boolean)]]) }
        def generate_resolution_options(repo, query_string)
          resolution_options = QUERY_PARSER::RESOLUTION_OPTIONS
          unless SecretScanning::Features::Repo::CustomPatterns.new(repo).feature_available?
            resolution_options = resolution_options.reject { |item| item[:feature] == :custom_pattern }
          end

          resolution_options.map do |option|
            excluded = resolution_option_excluded?(query_string, option[:slug])
            {
              label: option[:label],
              slug: option[:slug],

              query: resolution_option_query(query_string, option[:slug], excluded),
              checked: resolution_option_checked?(query_string, option[:slug]),
              excluded: excluded
            }
          end
        end

        sig { params(query_string: String, resolution_slug: String, excluded: T::Boolean).returns(String) }
        def resolution_option_query(query_string, resolution_slug, excluded)
          qualifier = QUERY_PARSER::QUALIFIER_RESOLUTION
          qualifier = QUERY_PARSER.negate_qualifier(qualifier) if excluded
          SecurityCenter::SelectMenuComponentHelper.query_string(
            is_multiselect: true,
            qualifier_to_select: qualifier,
            qualifiers_to_remove: [qualifier],
            query: query_string,
            query_parser: QUERY_PARSER,
            slug: resolution_slug)
        end

        sig { params(query_string: String, resolution_slug: String).returns(T::Boolean) }
        def resolution_option_checked?(query_string, resolution_slug)
          SecurityCenter::SelectMenuComponentHelper.checked?(
            default_selected_slug: nil,
            qualifier: QUERY_PARSER::QUALIFIER_RESOLUTION,
            query: query_string,
            query_parser: QUERY_PARSER,
            slug: resolution_slug,
            use_default_selected_slug_on_invalid_values: false,
            valid_values: QUERY_PARSER::RESOLUTION_OPTIONS.map { |option| option[:slug] })
        end

        sig { params(query_string: String, resolution_slug: String).returns(T::Boolean) }
        def resolution_option_excluded?(query_string, resolution_slug)
          SecurityCenter::SelectMenuComponentHelper.checked?(
            default_selected_slug: nil,
            qualifier: QUERY_PARSER.negate_qualifier(QUERY_PARSER::QUALIFIER_RESOLUTION),
            query: query_string,
            query_parser: QUERY_PARSER,
            slug: resolution_slug,
            use_default_selected_slug_on_invalid_values: false,
            valid_values: QUERY_PARSER::RESOLUTION_OPTIONS.map { |option| option[:slug] })
        end

        sig { params(query_string: String).returns(T::Hash[Symbol, T.any(String, T::Boolean)]) }
        def validity_clear_all(query_string)
          {
            label: "Clear validity",
            slug: nil,
            query: SecurityCenter::SelectMenuComponentHelper.query_clear_all(
              qualifiers: [QUERY_PARSER::QUALIFIER_VALIDITY],
              query: query_string,
              query_parser: QUERY_PARSER),
            checked: false,
            excluded: false,
            hidden: !QUERY_PARSER.get_qualified_values(query_string, QUERY_PARSER::QUALIFIER_VALIDITY).any?
          }
        end

        sig { params(repo: Repository, query_string: String).returns(T::Array[T::Hash[Symbol, T.any(String, T::Boolean)]]) }
        def generate_validity_options(repo, query_string)
          QUERY_PARSER::VALIDITY_OPTIONS.map do |option|
            {
              label: option[:label],
              slug: option[:slug],

              query: validity_option_query(query_string, option[:slug]),
              checked: validity_option_checked?(query_string, option[:slug]),
            }
          end
        end

        sig { params(query_string: String, validity_slug: String).returns(String) }
        def validity_option_query(query_string, validity_slug)
          qualifier = QUERY_PARSER::QUALIFIER_VALIDITY
          SecurityCenter::SelectMenuComponentHelper.query_string(
            is_multiselect: true,
            qualifier_to_select: qualifier,
            qualifiers_to_remove: [qualifier],
            query: query_string,
            query_parser: QUERY_PARSER,
            slug: validity_slug)
        end

        sig { params(query_string: String, validity_slug: String).returns(T::Boolean) }
        def validity_option_checked?(query_string, validity_slug)
          SecurityCenter::SelectMenuComponentHelper.checked?(
            default_selected_slug: nil,
            qualifier: QUERY_PARSER::QUALIFIER_VALIDITY,
            query: query_string,
            query_parser: QUERY_PARSER,
            slug: validity_slug,
            use_default_selected_slug_on_invalid_values: false,
            valid_values: QUERY_PARSER::VALIDITY_OPTIONS.map { |option| option[:slug] })
        end

        sig { params(query_string: String).returns(T::Hash[Symbol, T.any(String, T::Boolean)]) }
        def bypassed_clear_all(query_string)
          {
            label: "Clear bypassed",
            slug: nil,
            query: SecurityCenter::SelectMenuComponentHelper.query_clear_all(
              qualifiers: [QUERY_PARSER::QUALIFIER_BYPASSED],
              query: query_string,
              query_parser: QUERY_PARSER),
            checked: false,
            excluded: false,
            hidden: !QUERY_PARSER.get_qualified_values(query_string, QUERY_PARSER::QUALIFIER_BYPASSED).any?
          }
        end

        sig { params(repo: Repository, query_string: String).returns(T::Array[T::Hash[Symbol, T.any(String, T::Boolean)]]) }
        def generate_bypassed_options(repo, query_string)
          QUERY_PARSER::BYPASSED_OPTIONS.map do |option|
            {
              label: option[:label],
              slug: option[:slug],

              query: bypassed_option_query(query_string, option[:slug]),
              checked: bypassed_option_checked?(query_string, option[:slug]),
            }
          end
        end

        sig { params(query_string: String, bypassed_slug: String).returns(String) }
        def bypassed_option_query(query_string, bypassed_slug)
          qualifier = QUERY_PARSER::QUALIFIER_BYPASSED
          SecurityCenter::SelectMenuComponentHelper.query_string(
            is_multiselect: true,
            qualifier_to_select: qualifier,
            qualifiers_to_remove: [qualifier],
            query: query_string,
            query_parser: QUERY_PARSER,
            slug: bypassed_slug)
        end

        sig { params(query_string: String, bypassed_slug: String).returns(T::Boolean) }
        def bypassed_option_checked?(query_string, bypassed_slug)
          SecurityCenter::SelectMenuComponentHelper.checked?(
            default_selected_slug: nil,
            qualifier: QUERY_PARSER::QUALIFIER_BYPASSED,
            query: query_string,
            query_parser: QUERY_PARSER,
            slug: bypassed_slug,
            use_default_selected_slug_on_invalid_values: false,
            valid_values: QUERY_PARSER::BYPASSED_OPTIONS.map { |option| option[:slug] })
        end

        sig { params(repo: Repository, query_string: String).returns(T::Array[T::Hash[Symbol, T.any(String, T::Boolean)]]) }
        def generate_results_category_options(repo, query_string)
          results_category_options = QUERY_PARSER::RESULTS_CATEGORIES
          results_category_options.map do |option|
            excluded = results_category_option_excluded?(query_string, option)
            {
              label: results_category_option_label(option),
              slug: option,
              query: results_category_option_query(query_string, option, excluded),
              checked: results_category_option_checked?(query_string, option),
              excluded: excluded,
              count: results_category_option_label(option) == "Generic" ? generic_results_count : nil
            }
          end
        end

        sig { params(results_category_slug: String).returns(String) }
        def results_category_option_label(results_category_slug)
          case results_category_slug
          when QUERY_PARSER::DEFAULT_RESULTS_CATEGORY
            return "Default"
          when QUERY_PARSER::GENERIC_RESULTS
            return "Generic"
          end
          results_category_slug.capitalize
        end

        sig { params(query_string: String, results_category_slug: String, excluded: T::Boolean).returns(String) }
        def results_category_option_query(query_string, results_category_slug, excluded)
          SecurityCenter::SelectMenuComponentHelper.query_string(
            is_multiselect: false, # the results selector is not multiselect
            qualifier_to_select: QUERY_PARSER::QUALIFIER_RESULTS_CATEGORY,
            qualifiers_to_remove: [QUERY_PARSER::QUALIFIER_RESULTS_CATEGORY, QUERY_PARSER.negate_qualifier(QUERY_PARSER::QUALIFIER_RESULTS_CATEGORY)],
            query: query_string,
            query_parser: QUERY_PARSER,
            slug: results_category_slug)
        end

        sig { params(query_string: String, results_category_slug: String).returns(T::Boolean) }
        def results_category_option_checked?(query_string, results_category_slug)
          SecurityCenter::SelectMenuComponentHelper.checked?(
            default_selected_slug: QUERY_PARSER::DEFAULT_RESULTS_CATEGORY,
            qualifier: QUERY_PARSER::QUALIFIER_RESULTS_CATEGORY,
            query: query_string,
            query_parser: QUERY_PARSER,
            slug: results_category_slug,
            use_default_selected_slug_on_invalid_values: true,
            valid_values: QUERY_PARSER::RESULTS_CATEGORIES)
        end

        sig { params(query_string: String, results_category_slug: String).returns(T::Boolean) }
        def results_category_option_excluded?(query_string, results_category_slug)
          SecurityCenter::SelectMenuComponentHelper.checked?(
            default_selected_slug: nil,
            qualifier: QUERY_PARSER.negate_qualifier(QUERY_PARSER::QUALIFIER_RESULTS_CATEGORY),
            query: query_string,
            query_parser: QUERY_PARSER,
            slug: results_category_slug,
            use_default_selected_slug_on_invalid_values: false,
            valid_values: QUERY_PARSER::RESULTS_CATEGORIES)
        end

        sig { params(query_string: String).returns(T::Hash[Symbol, T.any(String, T::Boolean)]) }
        def secret_type_clear_all(query_string)
          {
            label: "Clear secret types",
            slug: nil,
            query: SecurityCenter::SelectMenuComponentHelper.query_clear_all(
              qualifiers: [QUERY_PARSER::QUALIFIER_SECRET_TYPE],
              query: query_string,
              query_parser: QUERY_PARSER),
            checked: false,
            excluded: false,
            hidden: !QUERY_PARSER.get_qualified_values(query_string, QUERY_PARSER::QUALIFIER_SECRET_TYPE).any?
          }
        end

        sig { params(query_string: String).returns(T::Hash[Symbol, T.any(String, T::Boolean)]) }
        def provider_clear_all(query_string)
          {
            label: "Clear providers",
            slug: nil,
            query: SecurityCenter::SelectMenuComponentHelper.query_clear_all(
              qualifiers: [QUERY_PARSER::QUALIFIER_PROVIDER],
              query: query_string,
              query_parser: QUERY_PARSER),
            checked: false,
            excluded: false,
            hidden: !QUERY_PARSER.get_qualified_values(query_string, QUERY_PARSER::QUALIFIER_PROVIDER).any?
          }
        end

        sig { params(query_string: String, secret_type_slug: String, excluded: T::Boolean).returns(String) }
        def secret_type_option_query(query_string, secret_type_slug, excluded)
          qualifier = QUERY_PARSER::QUALIFIER_SECRET_TYPE
          qualifier = QUERY_PARSER.negate_qualifier(qualifier) if excluded

          SecurityCenter::SelectMenuComponentHelper.query_string(
            is_multiselect: true,
            qualifier_to_select: qualifier,
            qualifiers_to_remove: [qualifier],
            query: query_string,
            query_parser: QUERY_PARSER,
            slug: secret_type_slug)
        end

        sig { params(query_string: String, secret_type_slug: String).returns(T::Boolean) }
        def secret_type_option_checked?(query_string, secret_type_slug)
          SecurityCenter::SelectMenuComponentHelper.checked?(
            default_selected_slug: nil,
            qualifier: QUERY_PARSER::QUALIFIER_SECRET_TYPE,
            query: query_string,
            query_parser: QUERY_PARSER,
            slug: secret_type_slug,
            use_default_selected_slug_on_invalid_values: false,
            valid_values: QUERY_PARSER::RESOLUTION_OPTIONS.map { |option| option[:slug] })
        end

        sig { params(query_string: String, secret_type_slug: String).returns(T::Boolean) }
        def secret_type_option_excluded?(query_string, secret_type_slug)
          SecurityCenter::SelectMenuComponentHelper.checked?(
            default_selected_slug: nil,
            qualifier: QUERY_PARSER.negate_qualifier(QUERY_PARSER::QUALIFIER_SECRET_TYPE),
            query: query_string,
            query_parser: QUERY_PARSER,
            slug: secret_type_slug,
            use_default_selected_slug_on_invalid_values: false,
            valid_values: QUERY_PARSER::RESOLUTION_OPTIONS.map { |option| option[:slug] })
        end

        sig { params(query_string: String, provider_slug: String, excluded: T::Boolean).returns(String) }
        def provider_option_query(query_string, provider_slug, excluded)
          qualifier = QUERY_PARSER::QUALIFIER_PROVIDER
          qualifier = QUERY_PARSER.negate_qualifier(qualifier) if excluded

          SecurityCenter::SelectMenuComponentHelper.query_string(
            is_multiselect: true,
            qualifier_to_select: qualifier,
            qualifiers_to_remove: [qualifier],
            query: query_string,
            query_parser: QUERY_PARSER,
            slug: provider_slug)
        end

        sig { params(query_string: String, provider_slug: String).returns(T::Boolean) }
        def provider_option_checked?(query_string, provider_slug)
          SecurityCenter::SelectMenuComponentHelper.checked?(
            default_selected_slug: nil,
            qualifier: QUERY_PARSER::QUALIFIER_PROVIDER,
            query: query_string,
            query_parser: QUERY_PARSER,
            slug: provider_slug,
            use_default_selected_slug_on_invalid_values: false,
            valid_values: QUERY_PARSER::RESOLUTION_OPTIONS.map { |option| option[:slug] })
        end

        sig { params(query_string: String, provider_slug: String).returns(T::Boolean) }
        def provider_option_excluded?(query_string, provider_slug)
          SecurityCenter::SelectMenuComponentHelper.checked?(
            default_selected_slug: nil,
            qualifier: QUERY_PARSER.negate_qualifier(QUERY_PARSER::QUALIFIER_PROVIDER),
            query: query_string,
            query_parser: QUERY_PARSER,
            slug: provider_slug,
            use_default_selected_slug_on_invalid_values: false,
            valid_values: QUERY_PARSER::RESOLUTION_OPTIONS.map { |option| option[:slug] })
        end

        sig { returns(T::Boolean) }
        def show_results_category?
          SecretScanning::Features::Repo::GenericSecrets.new(@repo).feature_available? ||
          SecretScanning::Features::Repo::LowerConfidencePatterns.new(@repo).feature_available?
        end

        sig { returns(Integer) }
        def generic_results_count
          req = {
            feature_flags: get_tokens_api_feature_flags(@repo),
            low_confidence: true,
          }
          unless @repo.nil?
            req[:repo_selector] = {
              repository_id: @repo.id,
            }
          end
          count = GitHub::TokenScanning::Service::Client.new(@user).get_token_counts(req)&.data&.unresolved_count
          count.nil? ? 0 : count
        end

        sig { params(repo: Repository, query_string: String).returns(T::Array[T::Hash[Symbol, T.any(String, T::Boolean)]]) }
        def generate_campaign_options(repo, query_string)
          QUERY_PARSER::CAMPAIGN_OPTIONS.map do |option|
            {
              label: option[:label],
              slug: option[:slug],

              query: campaign_option_query(query_string, option[:slug]),
              checked: campaign_option_checked?(query_string, option[:slug]),
            }
          end
        end

        sig { params(query_string: String).returns(T::Hash[Symbol, T.any(String, T::Boolean)]) }
        def campaign_clear_all(query_string)
          {
            label: "Clear campaigns",
            slug: nil,
            query: SecurityCenter::SelectMenuComponentHelper.query_clear_all(
              qualifiers: [QUERY_PARSER::QUALIFIER_CAMPAIGN],
              query: query_string,
              query_parser: QUERY_PARSER),
            checked: false,
            excluded: false,
            hidden: !QUERY_PARSER.get_qualified_values(query_string, QUERY_PARSER::QUALIFIER_CAMPAIGN).any?
          }
        end

        sig { params(query_string: String, campaign_slug: String).returns(String) }
        def campaign_option_query(query_string, campaign_slug)
          qualifier = QUERY_PARSER::QUALIFIER_CAMPAIGN
          SecurityCenter::SelectMenuComponentHelper.query_string(
            is_multiselect: true,
            qualifier_to_select: qualifier,
            qualifiers_to_remove: [qualifier],
            query: query_string,
            query_parser: QUERY_PARSER,
            slug: campaign_slug)
        end

        sig { params(query_string: String, campaign_slug: String).returns(T::Boolean) }
        def campaign_option_checked?(query_string, campaign_slug)
          SecurityCenter::SelectMenuComponentHelper.checked?(
            default_selected_slug: nil,
            qualifier: QUERY_PARSER::QUALIFIER_CAMPAIGN,
            query: query_string,
            query_parser: QUERY_PARSER,
            slug: campaign_slug,
            use_default_selected_slug_on_invalid_values: false,
            valid_values: QUERY_PARSER::CAMPAIGN_OPTIONS.map { |option| option[:slug] })
        end
      end
    end
  end
end
