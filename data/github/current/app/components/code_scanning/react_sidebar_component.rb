# typed: strict
# frozen_string_literal: true

class CodeScanning::ReactSidebarComponent < ApplicationComponent
  sig do
    params(
      repository: Repository,
      response: Twirp::ClientResp[Turboscan::Proto::AlertResponse],
      alert_title: String,
      severity_filter_url: String,
      current_user: T::Hash[Symbol, T.untyped],
      copilot_bot: T.nilable(T::Hash[Symbol, T.untyped]),
      assignees: T::Array[T::Hash[Symbol, T.untyped]],
      assignable_to_copilot: T::Boolean,
      suggested_fix: T.nilable(Turboscan::Proto::SuggestedFix),
      use_agentic_autofix: T::Boolean,
      config_statuses: T.nilable(T::Array[Turboscan::Proto::AlertConfigurationStatus]),
      config_statuses_complete: T.nilable(T::Boolean),
      alert_links: T::Array[CodeScanning::AlertLink],
      runtime_risks: T.nilable(T::Array[String]),
      tracking_links: T.nilable(T::Array[T::Hash[Symbol, T.untyped]]),
      show_alert_with_suggested_fix: T::Boolean,
      branch_list_cache_key: String,
      linked_branches: T::Array[T::Hash[Symbol, T.untyped]],
      linked_pull_requests: T::Array[T::Hash[Symbol, T.untyped]],
      campaigns_with_counts: T::Array[SecurityCampaigns::CampaignWithCounts],
      system_arguments: T.untyped,
    ).void
  end
  def initialize(
    repository:,
    response:,
    alert_title:,
    severity_filter_url:,
    current_user:,
    copilot_bot:,
    assignees:,
    assignable_to_copilot:,
    suggested_fix:,
    use_agentic_autofix:,
    config_statuses:,
    config_statuses_complete:,
    alert_links:,
    runtime_risks:,
    tracking_links:,
    show_alert_with_suggested_fix:,
    branch_list_cache_key:,
    linked_branches:,
    linked_pull_requests:,
    campaigns_with_counts:,
    **system_arguments
  )
    @repository = repository
    @response = response
    @alert_title = alert_title
    @severity_filter_url = severity_filter_url
    @current_user = current_user
    @copilot_bot = copilot_bot
    @assignees = assignees
    @assignable_to_copilot = assignable_to_copilot
    @suggested_fix = suggested_fix
    @use_agentic_autofix = use_agentic_autofix
    @config_statuses = config_statuses
    @config_statuses_complete = config_statuses_complete
    @alert_links = alert_links
    @tracking_links = tracking_links
    @show_alert_with_suggested_fix = show_alert_with_suggested_fix
    @branch_list_cache_key = branch_list_cache_key
    @linked_branches = linked_branches
    @linked_pull_requests = linked_pull_requests
    @campaigns_with_counts = campaigns_with_counts
    @runtime_risks = runtime_risks
    @system_arguments = system_arguments
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def sidebar_props
    {
      alertNumber: result.number,
      alertTitle: @alert_title,
      state: state,
      repository: {
        id: @repository.id,
        name: @repository.name,
        ownerLogin: @repository.owner&.display_login,
        defaultBranch: @repository.default_branch,
      },
      canWriteAlert: @repository.code_scanning_alerts_writable_by?(current_user),

      # Severity section
      ruleSeverity: rule_severity,
      securitySeverity: security_severity,
      severityFilterUrl: @severity_filter_url,

      # Assignee section
      currentUser: @current_user,
      copilotBot: @copilot_bot,
      assignees: @assignees,
      assignableToCopilot: @assignable_to_copilot,
      hasValidSuggestedFix: @suggested_fix.present? && !@suggested_fix.outdated,
      suggestedFixAliveChannel: live_update_view_channel(GitHub::WebSocket::Channels.code_scanning_alert(@repository, alert_number: result.number)),
      useAgenticAutofix: @use_agentic_autofix,

      # Affected branches section
      affectedBranches: affected_branches.affected_branches,
      additionalHiddenBranchesCount: affected_branches.additional_hidden_branches_count,
      hasAdditionalHiddenBranches: affected_branches.has_additional_hidden_branches,
      staleAlertsDocsUrl: DocsUrlConfig.url_for("code-security/removing-stale-configurations"),

      # Tracking section
      trackingSectionEnabled: !@tracking_links.nil?,
      trackingLinks: @tracking_links || [],

      # Development section
      hasSuggestedFix: @show_alert_with_suggested_fix,
      pushableByUser: @repository.pushable_by?(current_user),
      branchListCacheKey: @branch_list_cache_key,
      linkedBranches: @linked_branches,
      linkedPullRequests: @linked_pull_requests,

      # Security campaigns section
      securityCampaigns: @repository.owner.present? && SecurityCampaigns.enabled?(T.must(@repository.owner)) ? security_campaigns : nil,

      # Tags section
      ruleTags: rule_tags,

      # Runtime risks section
      runtimeRisksSectionEnabled: !@runtime_risks.nil?,
      runtimeRisks: @runtime_risks || [],

      # Weaknesses section
      cweNumbers: cwe_numbers,
    }
  end

  private

  sig { returns(Turboscan::Proto::Result) }
  def result
    T.must(@response.data.result)
  end

  sig { returns(String) }
  def rule_severity
    result.rule_severity.to_s.downcase
  end

  sig { returns(T.nilable(String)) }
  def security_severity
    security_severity = result.security_severity
    security_severity = Turboscan::Proto::SecuritySeverity.lookup(security_severity) if security_severity.is_a?(Integer)

    if security_severity == :NO_SECURITY_SEVERITY
      nil
    else
      security_severity&.to_s&.downcase
    end
  end

  sig { returns(Symbol) }
  def state
    if result.resolution.present? && result.resolution != :NO_RESOLUTION
      :dismissed
    elsif @response.data.ref_name_bytes != @repository.default_branch_ref.qualified_name
      if @response.data.ref_name_bytes.starts_with?("refs/pull/")
        :in_pr
      elsif @response.data.ref_name_bytes.starts_with?("refs/heads/")
        :in_branch
      else
        # I think this should never happen, but perhaps people can upload analysis with other refs?
        :unknown
      end
    elsif result.is_fixed
      :fixed
    else
      :open
    end
  end

  class AffectedBranches < T::Struct
    const :affected_branches, T.nilable(T::Array[T::Hash[Symbol, T.untyped]])
    const :additional_hidden_branches_count, Integer
    const :has_additional_hidden_branches, T::Boolean
  end

  PR_MERGE_COMMIT_REGEX = /\AMerge pull request #(\d+)/

  sig { returns(AffectedBranches) }
  memoize def affected_branches
    return AffectedBranches.new(
      affected_branches: nil,
      additional_hidden_branches_count: 0,
      has_additional_hidden_branches: false,
    ) if @config_statuses.nil?

    return AffectedBranches.new(
      affected_branches: [],
      additional_hidden_branches_count: 0,
      has_additional_hidden_branches: !@config_statuses_complete,
    ) if @config_statuses.empty?

    configs_by_branch = Hash.new { |h, k| h[k] = [] }
    @config_statuses.each do |config|
      branch_name = config.ref_name_bytes.dup.force_encoding(Encoding::UTF_8).scrub
      configs_by_branch[branch_name.delete_prefix("refs/heads/")].push(config)
    end

    protected_branch_names = @repository.protected_branches.map(&:name).to_set

    ordered_branches = configs_by_branch.keys.sort do |a, b|
      # default branch first
      next -1 if a == @repository.default_branch
      next 1 if b == @repository.default_branch

      # then protected branches
      next -1 if protected_branch_names.include?(a) && protected_branch_names.none?(b)
      next 1 if protected_branch_names.include?(b) && protected_branch_names.none?(a)

      # secondary ordering is name
      a <=> b
    end

    branches_to_show = ordered_branches.first(15)

    fixed_at_oids = branches_to_show.flat_map do |branch|
      configs = configs_by_branch[branch].filter_map do |config|
        config.fixed_at_oid.presence
      end
    end
    fixed_at_oids = fixed_at_oids.compact.uniq

    fixed_at_commits = if fixed_at_oids.present?
      begin
        @repository.commits.find(fixed_at_oids)
      rescue GitRPC::ObjectMissing
        []
      end.index_by(&:oid)
    else
      {}
    end

    affected_branches = branches_to_show.map do |branch|
      configs = configs_by_branch[branch].map do |config|
        hash = {
          category: config.category,
          toolName: config.tool,
          createdAt: config.created_at&.to_time,
          fixedAt: config.fixed_at&.to_time,
        }

        commit = if config.fixed_at_oid.present?
          fixed_at_commits[config.fixed_at_oid]
        else
          nil
        end

        hash[:fixCommit] = if commit.present?
          commit_hash = {
            oid: commit.oid,
            shortOid: commit.abbreviated_oid,
            isMergeCommit: commit.merge_commit?,
            message: commit.message,
          }
          if commit.merge_commit?
            pr_number_match = PR_MERGE_COMMIT_REGEX.match(commit.message_text)
            if pr_number_match
              commit_hash[:pullRequest] = {
                number: pr_number_match[1].to_i,
              }
            end
          end
          commit_hash[:pullRequest] ||= nil
          commit_hash
        else
          nil
        end

        hash
      end

      # We try finding PRs that fix the alert in this branch by finding PRs targeting this branch.
      pr_alert_links = @alert_links.filter { |link| link.pull_request&.base_ref == branch && link.pull_request&.state == :open }
        .sort_by { |link| link.pull_request&.updated_at }
        .reverse

      if pr_alert_links.length > 1
        GitHub.logger.info(
          "Found multiple pull requests for fixing alert in the same branch",
          "gh.branch.name": branch,
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.repo.id": @repository.id,
          "gh.pull_request.ids": pr_alert_links.map { |link| link.pull_request&.id }.join(","),
          "gh.pull_request.numbers": pr_alert_links.map { |link| link.pull_request&.number }.join(","),
        )
      end

      fixing_pr = pr_alert_links.first&.pull_request

      {
        name: branch,
        dismissed: result.resolution.present? && result.resolution != :NO_RESOLUTION,
        configs:,
        isDefaultBranch: @repository.default_branch == branch,
        linkedPullRequest: if fixing_pr.present?
                             {
                               number: fixing_pr.number,
                             }
                           else
                             nil
                           end,
      }
    end

    # Note that the how_many_more only considers branches from fetched instances
    # If we did not get all tips from Turboscan the view will present it as a lower bound
    plus_this_many_more = ordered_branches.size - branches_to_show.size

    AffectedBranches.new(
      affected_branches: affected_branches,
      additional_hidden_branches_count: plus_this_many_more,
      has_additional_hidden_branches: !@config_statuses_complete,
    )
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def rule_tags
    rule_tags_for_tags_section.map do |tag|
      {
        name: rule_tag_label(tag),
        path: tag_path(tag),
      }
    end
  end

  sig { params(tag: String).returns(String) }
  def tag_path(tag)
    query_params = [[:tag, tag], [:is, :open]]
    tool_name = result.tool&.name
    query_params << [:tool, tool_name] if tool_name.present?
    tag_query = Search::Query.stringify(query_params)

    return "" if @repository.owner.nil?

    UrlHelpers.repository_code_scanning_results_path(@repository.owner, @repository, query: tag_query)
  end

  sig { returns(T::Array[String]) }
  def all_rule_tags
    @response.data.rule_tags.to_a
  end

  sig { returns(T::Array[String]) }
  memoize def rule_tags_for_tags_section
    all_rule_tags - cwe_tags
  end

  sig { returns(T::Array[String]) }
  memoize def cwe_tags
    all_rule_tags.filter do |tag|
      rule_tag_label(tag).starts_with? "CWE-"
    end
  end

  sig { returns(T::Array[Integer]) }
  memoize def cwe_numbers
    cwe_numbers = cwe_tags.map do |tag|
      cwe_id(tag)
    end
    cwe_numbers.compact
  end

  CWE_PATTERN = T.let(/cwe(?:[- ]*0*)(\d+)/i.freeze, Regexp)

  sig { params(rule_tag: String).returns(String) }
  def rule_tag_label(rule_tag)
    # Drop external/cwe/ prefix
    rule_tag = rule_tag.gsub(/\Aexternal\/cwe\/(cwe-[\d]+)\z/, "\\1")

    rule_tag = rule_tag.titleize.downcase

    # Normalize cwe 012 to CWE-12
    rule_tag = rule_tag.gsub(CWE_PATTERN, "CWE-\\1")
  end

  sig { params(rule_tag: String).returns(T.nilable(Integer)) }
  def cwe_id(rule_tag)
    match = CWE_PATTERN.match(rule_tag)
    match.present? ? match[1].to_i : nil
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def security_campaigns
    @campaigns_with_counts.map do |campaign_with_counts|
      {
        number: campaign_with_counts.security_campaign.number,
        name: campaign_with_counts.security_campaign.name,
        percentageComplete: campaign_with_counts.closed_percentage,
        endsAt: campaign_with_counts.security_campaign.ends_at,
      }
    end
  end
end
