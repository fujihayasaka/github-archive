# typed: true
# frozen_string_literal: true

class Issue
  class SearchResult
    MYSQL_OVERLOAD_ERROR_TYPES = [
      ActiveRecord::StatementTimeout,
      ActiveRecord::QueryCanceled,
      ActiveRecord::ConnectionTimeoutError,
    ].freeze

    extend ActionView::Helpers::CaptureHelper
    extend ResilienceHelper
    extend Scientist

    # Run the search over MySQL or Elastic Search, depending on the query.
    #
    # Returns an Array of Issues.
    def self.search(query:, repo: nil, prefill_associations: true, exclude_prefills: [], tags: [], **kargs)
      pulls_index_request = (kargs[:pulls_index_request] || false)

      GitHub.tracer.in_span("Issue::SearchResult.search", kind: :internal) do |span|
        # Manual mysql-only mode: force a minimal PR-only MySQL listing path and
        # signal the UI to disable advanced filtering.
        mysql_only_mode = pulls_index_request && repo &&
          repo.feature_flag_enabled?(:pulls_mysql_only_mode, default: false)

        backend = if mysql_only_mode
          backend_name = "mysql_pulls_minimal"
          nil
        elsif pulls_index_request && repo && repo.feature_flag_enabled?(:mysql_search_override, default: false) && MysqlSearch.supported?(query, kargs[:current_user])
          backend_name = "mysql"
          MysqlSearch
        else
          backend_name = "elasticsearch"
          EsSearch
        end

        tags << "context:#{kargs[:context]}" if kargs[:context]

        # Make sure the page values look appropriate before passing them on.
        page              = (kargs[:page] || 1).to_i
        per_page          = (kargs[:per_page] || 25).to_i
        force_pulls       = (kargs[:force_pulls] || false)
        kargs[:page]      = page > 0 ? page : 1
        kargs[:per_page]  = per_page > 0 ? per_page : 25

        # tags from kargs
        span_attributes = {
          "page" => page,
          "per_page" => per_page,
          "backend" => backend_name,
          "prefill" => prefill_associations,
          "has_repo" => !repo.nil?,
          "exclude_prefils" => !exclude_prefills.empty?,
        }
        span.add_attributes(span_attributes)

        tags.concat(span_attributes.map { |k, v| "#{k}:#{v}" })
        results = begin
          Issue::SearchMetrics.track "issue.search.query.time", tags: tags do
            if mysql_only_mode
              begin
                mysql_only_pulls_search(
                  query: query,
                  repo: T.must(repo),
                  page: kargs[:page],
                  per_page: kargs[:per_page],
                  current_user: kargs[:current_user],
                  show_spam_to_staff: kargs[:show_spam_to_staff],
                )
              rescue *MYSQL_OVERLOAD_ERROR_TYPES => mysql_error
                # we can disable too and keep to old behavior of raising by turning flag off
                raise unless mysql_overload_fallback_enabled?(repo)

                overload_tags = tags + ["reason:mysql_overloaded"]
                GitHub.dogstats.increment("issue.search.mysql_fallback", tags: overload_tags)
                GitHub.logger.warn("issue.search.mysql_fallback", {
                  "code.namespace" => "Issue::SearchResult",
                  "repository_id" => repo.id,
                  "repository_nwo" => repo.name_with_display_owner,
                  "error_class" => mysql_error.class.name,
                  "error_message" => mysql_error.message,
                })
                mysql_overloaded_result
              end
            else
              T.unsafe(backend).search(query: query, repo: repo, force_pulls: force_pulls, pulls_index_request: pulls_index_request, tags: tags, **kargs)
            end
          end
        rescue ElastomerClient::Client::Error => e
          if pulls_index_request && backend_name == "elasticsearch" && repo
            # Automatic fallback: ES is unavailable, retry with MySQL on a stripped query.
            mysql_only_mode = true
            fallback_tags = tags + ["reason:elastomer_client_error"]
            GitHub.dogstats.increment("issue.search.mysql_fallback", tags: fallback_tags)
            GitHub.logger.warn("issue.search.mysql_fallback", {
              "code.namespace" => "Issue::SearchResult",
              "repository_id" => repo.id,
              "repository_nwo" => repo.name_with_display_owner,
              "error_class" => e.class.name,
              "error_message" => e.message,
            })
            Issue::SearchMetrics.track "issue.search.query.time", tags: tags + ["backend:mysql_fallback"] do
              begin
                mysql_only_pulls_search(
                  query: query,
                  repo: T.must(repo),
                  page: kargs[:page],
                  per_page: kargs[:per_page],
                  current_user: kargs[:current_user],
                  show_spam_to_staff: kargs[:show_spam_to_staff],
                )
              rescue *MYSQL_OVERLOAD_ERROR_TYPES => mysql_error
                # we can disable too and keep to old behavior of raising by turning flag off
                raise unless mysql_overload_fallback_enabled?(repo)

                overload_tags = tags + ["reason:mysql_overloaded"]
                GitHub.dogstats.increment("issue.search.mysql_fallback", tags: overload_tags)
                GitHub.logger.warn("issue.search.mysql_fallback", {
                  "code.namespace" => "Issue::SearchResult",
                  "repository_id" => repo.id,
                  "repository_nwo" => repo.name_with_display_owner,
                  "error_class" => mysql_error.class.name,
                  "error_message" => mysql_error.message,
                })
                mysql_overloaded_result
              end
            end
          else
            raise
          end
        end

        if repo && prefill_associations
          Issue::SearchMetrics.track "issue.search.query.prefill-assoc.time", tags: tags do
            current_user = kargs[:current_user]
            IssuePrefiller.prefill(results[:issues], repository: repo, current_user: current_user,
                                                   exclude_prefills: exclude_prefills, tags: tags)

            if query && query.is_a?(Array)
              sort = query.select { |c| c.is_a?(Array) && c.first == :sort }.flatten.try(:second)
              if sort && sort.match(/reactions-(.*)-(desc|asc)/)
                issues = results[:issues]
                emotion = $1
                GitHub::PrefillAssociations.prefill_batch_method(issues, :prelude_reaction_count_for_reaction, emotion)
              end
            end

            Issue::SearchMetrics.track "issue.search.query.prefill-pulls.time", tags: tags do
              pull_requests = results[:issues].map(&:pull_request).compact
              if pull_requests.any?
                PullRequest.prefill_associations(pull_requests, issues: results[:issues])
                GitHub::PrefillAssociations.prefill_batch_method(pull_requests, :base_branch_rule_evaluator)

                # prefilling required_status_checks for the protected branches we found
                GitHub::PrefillAssociations.prefill_associations(pull_requests.map(&:base_branch_rule_evaluator).compact
                  .map(&:original_protected_branch), :required_status_checks)
              end
            end
          end
        end

        if kargs[:current_user]
          read_issues = Issue.read_for(kargs[:current_user], results[:issues])
          results[:issues].each do |issue|
            issue.read_by_current_user = read_issues.include?(issue.id)
          end
        end

        results[:mysql_only] = true if mysql_only_mode
        results
      end
    end

    def self.mysql_only_pulls_search(query:, repo:, page:, per_page:, current_user: nil, show_spam_to_staff: false)
      parsed_query = Search::Queries::IssueQuery.coerce(query, current_user)
      state_filter = pulls_state_filter(parsed_query)

      if Issue::MysqlSearch.repo_spammy_for?(repo, current_user, show_spam_to_staff)
        base_scope = repo.issues.none
      else
        base_scope = repo.issues.with_pull_requests
        base_scope = base_scope.filter_spam_for(current_user, show_spam_to_staff: show_spam_to_staff)
      end

      open_count = base_scope.where(state: "open").count
      closed_count = base_scope.where(state: "closed").count
      scope = case state_filter
      when "open"
        base_scope.where(state: "open")
      when "closed"
        base_scope.where(state: "closed")
      else
        base_scope
      end

      offset = (page - 1) * per_page
      max_offset = Search::Queries::IssueQuery::MAX_PULL_REQUEST_OFFSET
      issues = if offset >= max_offset
        []
      else
        limited_per_page = [per_page, max_offset - offset].min
        scope.order(updated_at: :desc, id: :desc).paginate(page:, per_page: limited_per_page).to_a
      end

      { issues: issues, open_count: open_count, closed_count: closed_count }
    end

    def self.pulls_state_filter(parsed_query)
      return nil unless parsed_query.is_a?(Array)

      filters = []
      parsed_query.each do |component|
        return nil unless component.is_a?(Array)

        key = component[0]
        value = component[1]
        negated = component[2]

        next unless %i[is state].include?(key)
        next unless %w[open closed].include?(value)

        return nil if negated

        filters << value
      end

      return nil if filters.empty?

      filters.uniq.one? ? filters.first : nil
    end

    def self.mysql_overload_fallback_enabled?(repo)
      repo.feature_flag_enabled?(:pulls_mysql_overload_fallback, default: false)
    end

    def self.mysql_overloaded_result
      {
        issues: [],
        open_count: 0,
        closed_count: 0,
        search_temporarily_unavailable: true,
      }
    end

    private_class_method :mysql_only_pulls_search, :pulls_state_filter, :mysql_overload_fallback_enabled?, :mysql_overloaded_result
  end
end
