# typed: true
# frozen_string_literal: true

class Issue
  class SearchResult
    extend ActionView::Helpers::CaptureHelper
    extend ResilienceHelper
    extend Scientist

    # Run the search over MySQL or Elastic Search, depending on the query.
    #
    # Returns an Array of Issues.
    def self.search(query:, repo: nil, prefill_associations: true, exclude_prefills: [], tags: [], **kargs)
      pulls_index_request = (kargs[:pulls_index_request] || false)

      GitHub.tracer.in_span("Issue::SearchResult.search", kind: :internal) do |span|
        backend = if repo && repo.feature_flag_enabled?(:mysql_search_override, default: false) && MysqlSearch.supported?(query, kargs[:current_user])
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
        results = Issue::SearchMetrics.track "issue.search.query.time", tags: tags do
          T.unsafe(backend).search(query: query, repo: repo, force_pulls: force_pulls, pulls_index_request: pulls_index_request, tags: tags, **kargs)
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

        results
      end
    end
  end
end
