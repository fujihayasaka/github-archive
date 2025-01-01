# typed: true
# frozen_string_literal: true

module RepositoryCodeScanning
  class IndexView < View
    include GitHub::Memoizer
    include DocsUrlHelper

    attr_reader :ref_names, :page, :per_page, :default_query_string, :tool_counts

    def results
      @results ||= WillPaginate::Collection.create(page, per_page, total_count) do |pager|
        pager.replace(response&.data&.results || [])
      end
    end

    def alert_results
      ar = response&.data&.results || []
      if ar.present?
        ar = ar.map { |r| CodeScanning::AlertResult.new(result: r, repository: repository) }
      end
      @alert_results ||= WillPaginate::Collection.create(page, per_page, total_count) do |pager|
        pager.replace(ar)
      end
    end

    def fixed_result_numbers
      if !closed?
        []
      else
        # Fixed results are those that are closed but not resolved
        @fixed_result_numbers ||=
          results
            .select { |result| !result_resolved?(result) }
            .map { |result| result.number }
      end
    end

    def open_count
      @open_count ||= response&.data&.open_count || 0
    end

    def closed_count
      @closed_count ||= response&.data&.resolved_count || 0
    end

    def total_count
      @total_count ||= response&.data&.total_count || 0
    end

    def rules
      @rules ||= response&.data&.rules || []
    end

    def rule_filters
      rules.uniq(&:sarif_identifier)
      .sort_by(&:sarif_identifier).map do |rule|
        {
          label: rule.short_description,
          id: rule.sarif_identifier,
          selected: query.qualifier_selected?(name: :rule, value: rule.sarif_identifier),
          url: index_path(query: query.add_or_remove(:rule, rule.sarif_identifier)),
        }
      end
    end

    def tag_filters
      rule_tags.sort.map do |tag|
        {
          label: tag,
          selected: query.qualifier_selected?(name: :tag, value: tag),
          url: index_path(query: query.toggle_qualifier(name: :tag, value: tag)),
        }
      end.unshift({
        label: "All",
        selected: !query.contains_qualifier?(name: :tag),
        url: index_path(query: query.replace_qualifier(name: :tag, value: nil)),
      })
    end

    def tool_status_path
      urls.repository_code_scanning_results_tool_status_path(repository.owner, repository)
    end

    def ref_selected?(ref)
      ref_names.include?(ref)
    end

    def ref_path(ref)
      index_path(query: query.set_reflike_qualifier(name: :ref, value: ref))
    end

    def branch_path(branch_name)
      index_path(query: query.set_reflike_qualifier(name: :branch, value: branch_name))
    end

    def pr_path(pr_number, base_query: nil)
      the_query = base_query || query
      index_path(query: the_query.set_reflike_qualifier(name: :pr, value: pr_number))
    end

    def code_scanning_1_click_settings_path
      urls.repository_security_and_analysis_path(repository.owner, repository, anchor: "code_scanning_settings")
    end

    def closed?
      query.closed?
    end

    def query_is_default
      query.query_string == default_query_string
    end

    def analysis_exists?
      # Does an analysis exist matching the current alert filters?
      response&.data&.analysis_exists
    end

    def show_pagination?
      results.total_pages > 1
    end

    def actions_enabled?
      GitHub.actions_enabled? && repository.actions_enabled?
    end

    def blank_slate_to_show
      no_analyses = !turboscan_unavailable? &&
        results.empty? &&
        !repository.code_scanning_analysis_exists?
      return nil unless no_analyses
      return :archived if repository.archived?

      if auto_codeql_waiting?
        :auto_codeql_waiting
      else
        :no_analyses
      end
    end

    def link_to_1_click_ui?
      can_manage_security_products?
    end

    def default_ref_name
      repository.default_branch_ref&.name || "master"
    end

    # Methods for the filter bar

    def classifications_for(result)
      classifications_for_alert_instance(result.most_recent_instance)
    end

    def protip
      @protip ||= protips.sample
    end

    def protips
      @protips ||= [
        { text: "You can run CodeQL locally using Visual Studio Code.", link_text: "Learn more", link_href: "https://github.com/github/vscode-codeql#codeql-for-visual-studio-code" },
        { text: "You can run CodeQL locally from the command line.", link_text: "Learn more", link_href: "https://github.com/github/codeql-cli-binaries#codeql-cli" },
        { text: "CodeQL queries are developed by an open-source coalition called the", link_text: "GitHub Security Lab", link_href: "https://securitylab.github.com" },
        { text: "You can upload code scanning analyses from other third-party tools using GitHub Actions.", link_text: "Learn more", link_href: docs_url("code-security/uploading-a-sarif-file-to-github") },
        { text: "You can configure CodeQL to run with additional queries.", link_text: "Learn more", link_href: docs_url("code-security/customizing-your-advanced-setup-for-code-scanning", fragment: "running-additional-queries") },
        { text: "The libraries and queries that power CodeQL are open-source.", link_text: "Learn more", link_href: "https://github.com/github/codeql" },
      ]
    end

    NO_RESULTS_MESSAGES_OPEN = [
      { heading: "No code scanning alerts here!", text: "Keep up the good work!" },
      { heading: "No code scanning alerts found.", text: "We'll keep watching out for new ones." },
      { heading: "Looking good!", text: "No new code scanning alerts." },
    ]

    def no_results_messages
      @no_results_messages ||= if !analysis_exists?
        no_analysis_message
      elsif !query_is_default
        [{ heading: "No results matched your search.", text: "" }]
      else
        NO_RESULTS_MESSAGES_OPEN
      end
    end

    def no_analysis_message
      docs = helpers.link_to("here", DocsUrlConfig.url_for("code-security/about-code-scanning"))
      no_analysis_text = helpers.safe_join(["For more information about code scanning, see ", docs, "."])
      if ref_names&.count == 1
        if ref_names[0].start_with?("refs/heads/")
          head_ref = ref_names[0].delete_prefix("refs/heads/")
          pr = repository.pull_requests.where(head_ref: head_ref).order(id: :desc).first
          if pr
            pr_number = pr.number
            pr_link = helpers.link_to("##{pr_number}", pr_path(pr_number))
            no_analysis_text = helpers.safe_join(["Are you looking for the alerts in pull request ", pr_link, "?"])
          end
        end
      end

      if ref_names&.count != 1
        [{ heading: "These branches haven't been scanned yet.", text: no_analysis_text }]
      else
        [{ heading: "This branch hasn't been scanned yet.", text: no_analysis_text }]
      end
    end

    def code_scanning_workflows_url
      "/#{repository.name_with_display_owner}/actions/new?category=security&query=code+scanning"
    end

    def codeql_language_documentation_url
      owner = repository.owner
      ghec = !!(owner.organization? && (owner.business || owner.business_plus?))
      docs_url("code-security/about-code-scanning-with-codeql", fragment: "about-codeql")
    end

    def text_search_warning_message
      return @text_search_warning_message if defined? @text_search_warning_message

      if query.search_query != ""
        @text_search_warning_message = "Free-text search is not currently available. Showing standard filtered results."
      end
    end

    private

    def can_manage_security_products?
      return @can_manage_security_products if defined?(@can_manage_security_products)

      @can_manage_security_products =
        if repository.owner&.organization?
          SecurityProduct::Permissions::RepoAuthz.new(repository, actor: current_user).can_manage_repo_security_products?
        else
          repository.adminable_by?(current_user)
        end
    end

    memoize def auto_codeql_waiting?
      auto_codeql = CodeScanning::AutoCodeql.new(repository)
      auto_codeql.waiting?
    end
  end
end
