# typed: true
# frozen_string_literal: true

module Repository::CodeScanningDependency
  extend T::Helpers
  requires_ancestor { Repository }

  include FeatureFlagHelper
  include Scientist
  include GitHub::Memoizer

  CODEQL_LANGUAGE_MAPPING = {
    "csharp": "csharp",
    "c#": "csharp",
    "cpp": "c-cpp",
    "c": "c-cpp",
    "c++": "c-cpp",
    "go": "go",
    "java": "java-kotlin",
    "javascript": "javascript-typescript",
    "typescript": "javascript-typescript",
    "python": "python",
    "ruby": "ruby",
    "kotlin": "java-kotlin",
    "swift": "swift",
  }.freeze

  CODEQL_BUILD_MAPPING = {
    "csharp": "none",
    "c-cpp": "autobuild",
    "go": "autobuild",
    "java-kotlin": "autobuild",
    "javascript-typescript": "none",
    "python": "none",
    "ruby": "none",
    "swift": "autobuild",
  }.freeze

  PULL_REQUEST_ANALYSIS_TIME_LIMIT = 6.hours

  # Should code scanning be shown on the overview page of the security tab
  def show_code_scanning?(current_user)
    return false unless GitHub.code_scanning_enabled? # config flag check
    return false if code_scanning_banned?

    # Show code scanning if feature is enabled for user and repo
    return true if code_scanning_readable_by?(current_user)

    # Hide the "enable in settings" link if GHAS usage is blocked by the policy
    return false if advanced_security_configurable? &&
        !advanced_security_enabled? &&
        !owner&.policy_allows_advanced_security_enablement?

    # Show code scanning if user is a repository admin and therefore
    # should see a button to enable code scanning
    return true if adminable_by?(current_user) && owner&.advanced_security_purchased?

    # The "contact sales" case below doesn't apply to Enterprise.
    return false if GitHub.enterprise?

    # Show code scanning if the current user
    # should see a "contact sales" link
    if owner&.organization?
      owner&.adminable_by?(current_user)
    else
      owner == current_user
    end
  end

  # Show code scanning workflows in actions:
  # 1. Code scanning workflows are shown to all users for enterprise repos irresespective of advanced security enabled or not or disabled by policy
  # 2. Code scanning workflows are not shown if the repo is personal private
  # 3. Code scanning workflows are not shown if advanced security is not purchased on GitHub.enterprise.
  # 4. Code scanning workflows are not shown for enterprise personal repos
  def show_code_scanning_workflows_in_actions?
    return false unless GitHub.code_scanning_enabled? # config flag check

    # Code scanning workflows are shown when code scanning is banned
    return false if code_scanning_banned?

    # On Enterprise instance, Code scanning workflows are not shown for personal repos
    return false if GitHub.enterprise? && !owner&.organization?

    # Show code scanning if feature is enabled for repo or advanced security is purchased.
    # Handles org/personal public repos on dotcom as well
    return true if code_scanning_enabled? || owner&.advanced_security_purchased?

    # Code scanning workflows are not shown if advanced security is not purchased on GitHub.enterprise.
    return false if GitHub.enterprise?

    # On dotcom, code scanning workflows are shown for org repos
    return true if owner&.organization?

    # Else dotcom personal private repository
    false
  end

  def code_scanning_banned?
    return false if GitHub.enterprise?
    feature_enabled?(:disable_code_scanning, memoize: false) || owner&.feature_enabled?(:disable_code_scanning, memoize: false)
  end

  def code_scanning_enterprise_disabled?
    return @code_scanning_enterprise_disabled if defined?(@code_scanning_enterprise_disabled)
    return @code_scanning_enterprise_disabled = true if code_scanning_disabled_for_enterprise_owned_users?
    return @code_scanning_enterprise_disabled = false if GitHub.enterprise?
    return @code_scanning_enterprise_disabled = false if public?
    @code_scanning_enterprise_disabled = owner&.business.present? && owner&.business.feature_enabled?(:code_scanning_enterprise_disabled)
  end

  # As part of https://github.com/github/secret-scanning/issues/4665,
  # GHAS and Secret Scanning were made available to user namespace repositories.
  # Code scanning does work within user namespace repositories, but isn't correctly
  # being aggregated at the enterprise level.
  #
  # This method is a temporary workaround to disable code scanning for user namespace repos
  # in an enterprise context (GHES or EMU cloud).
  def code_scanning_disabled_for_enterprise_owned_users?
    # First check if the repo is owned by a user
    if owner.is_a?(User) && owner&.user?
      return true if GitHub.enterprise?

      # Second check if the user is an EMU
      return owner&.is_enterprise_managed?
    end

    false
  end

  def code_scanning_usable?
    return false unless code_scanning_available?

    advanced_security_usable?
  end

  # @deprecated Use {#code_scanning_usable?} instead.
  def code_scanning_enabled?
    code_scanning_usable?
  end

  # Turboscan considers code scanning enabled if default setup is enabled
  # or the repository's default branch has an analysis for a tool.
  memoize def turboscan_considers_code_scanning_enabled?
    # Ideally, the turboscan endpoint should reflect a disabled state after repo deletion. However, there is a
    # potential delay until data is updated in the database. Therefore, we infer the deleted state here to avoid
    # discrepancy between turboscan state and expected state in dotcom.
    return false if repository.deleted?

    # Code scanning in non-public repositories has a prerequisite of advanced security being enabled.
    return false unless advanced_security_usable?

    default_ref_name_bytes = default_branch_ref&.qualified_name.present? ? default_branch_ref.qualified_name.b : ""
    response = GitHub::Turboscan.code_scanning_enabled?(
      repository_id: id,
      default_ref_name_bytes: default_ref_name_bytes
    )

    return false if response.blank? || response.error.present?

    response.data&.is_enabled
  end

  # Whether code scanning is available for this repository, for reasons outside the user's control.
  def code_scanning_available?
    return false unless GitHub.code_scanning_enabled? # config flag check
    return false unless owner.present?
    return false if code_scanning_banned?
    return false if code_scanning_enterprise_disabled?
    true
  end

  def show_code_scanning_annotations_ui?(user)
    code_scanning_enabled?
  end

  def async_code_scanning_allowed?(action, user)
    result =
      if user
        Platform::Loaders::Permissions::BatchAuthorize.load(
          action: action,
          actor: user,
          subject: self,
       )
      else
        Promise.resolve(Authzd::DENY)
      end

    result.then do |decision|
      if decision.error?
        Failbot.report(StandardError.new(decision.error),
                       "gh.code_scanning.authz_action": action,
                       "gh.repo.id": self&.id,
                       "gh.actor.login": user&.login)
      end
      decision.allow?
    end
  end

  def async_code_scanning_readable_by?(user)
    async_code_scanning_allowed?(:read_code_scanning, user)
  end

  # Checks if the user has permission to read Code Scanning alerts, but nothing else.
  # It does not care about enablement in any way.
  def code_scanning_readable_permission_check_only_by?(user)
    # On dotcom, grants hubbers read-only access to code scanning pages.
    # This functionality can be disabled by disabling employee mode (in the footer).
    # In the case of private repositories it is still required that the hubber has
    # gained read access to the repository through some means.
    if GitHub.dotcom_request? && user.present? && user.employee?
      return repository.readable_by?(user)
    end

    async_code_scanning_readable_by?(user).sync
  end

  # Checks if the user has permission to read Code Scanning alerts, and that Advanced Security is enabled.
  def code_scanning_readable_by?(user)
    return false unless code_scanning_usable?

    code_scanning_readable_permission_check_only_by?(user)
  end

  def code_scanning_alerts_readable_by?(user)
    code_scanning_readable_by?(user)
  end

  # Is the current user only able to read code scanning alerts because they are a employee / hubber
  def code_scanning_readable_because_hubber?(user)
    code_scanning_readable_by?(user) && !async_code_scanning_readable_by?(user).sync
  end

  # returns a boolean if user has write access
  # to code scanning feature on the repository
  def code_scanning_writable_by?(user)
    return false unless code_scanning_usable?
    async_code_scanning_allowed?(:write_code_scanning, user).sync
  end

  def code_scanning_alerts_writable_by?(user)
    !archived? && code_scanning_writable_by?(user)
  end

  def code_scanning_analyses_deletable_by?(user)
    return false unless code_scanning_usable?
    async_code_scanning_allowed?(:delete_alerts_code_scanning, user).sync
  end

  # Return true if this repo is
  #  - a repo on GHES, or
  #  - a private org-owned repo on Cloud
  # otherwise return false.
  def advanced_security_required_for_code_scanning?
    return true if GitHub.enterprise?
    private? && owner&.organization?
  end

  # returns true iff the repo requires advanced security to be enabled
  # in order to use code scanning, AND advanced security is not enabled.
  # Intended to be used alongside Committer Based Billing to prompt users
  # to turn on GHAS if that's possible.
  def code_scanning_disabled_by_advanced_security?
    return false unless advanced_security_required_for_code_scanning?
    !advanced_security_enabled?
  end

  # Get the default qualified ref names to use for code scanning.
  #
  # This currently only includes the default branch.
  memoize def default_code_scanning_ref_names_bytes
    [default_branch_ref&.qualified_name].compact
  end

  # Get the default qualified ref names to use for code scanning, excluding any that are not valid UTF-8 strings.
  # This can be removed when (or if) refs are eventually handled as bytes everywhere.
  #
  # This currently only includes the default branch.
  memoize def default_code_scanning_ref_names
    # TODO: we probably want to refactor this to have a different name
    # and only return a single element, but because we needed to backport this
    # we initially went for the smallest change.

    ref_names = default_code_scanning_ref_names_bytes
    ref_names = ref_names.map { |ref| ref.dup.force_encoding("UTF-8") }
    ref_names.uniq.select(&:valid_encoding?)
  end

  # Returns a list of protected branches in a format safe for use in the Code Scanning workflow file
  #
  # If the default branch is not protected, it'll never be returned by this method
  # If it _is_ protected, whether it's returned depends on the value passed as `exclude_default_branch`
  def protected_branches_for_code_scanning_workflow(exclude_default_branch:)
    # The protected branches are provided in the fnmatch syntax https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/managing-a-branch-protection-rule#about-branch-protection-rules
    # But the workflow uses a different syntax https://docs.github.com/actions/using-workflows/workflow-syntax-for-github-actions#filter-pattern-cheat-sheet

    # This is particulary problematic for the ? character.
    # In fnmatch syntax it means `Matches any one character. Equivalent to /.{1}/ in regexp.`
    # In the workflow syntax it means `Matches zero or one of the preceding character`
    # Having several ? together causes a syntax error while parsing the workflow file
    repository.protected_branches.filter_map do |branch|
      next if exclude_default_branch && branch.name == repository.default_branch

      # [a-zA-Z0-9] in workflow syntax means `Matches one character listed in the brackets`
      # which is the closest thing in meaning to ? in the original fnmatch syntax
      new_name = branch.name.gsub "?", "[a-zA-Z0-9]"

      # Force a JSON string in case the branch is not Yaml safe (e.g. globs)
      new_name.to_json
    end
  end

  memoize def detected_languages
    # We intentionally use `language_analysis` here rather than `repository.language_percentages` directly.
    # This is because `repository.language_percentages` has caching issues that cause the reported languages to be incorrect, particularly locally and on GitHub Enterprise.
    repository.language_analysis.language_percentages.map(&:first)
  end

  def codeql_language_mapping
    languages = CODEQL_LANGUAGE_MAPPING
    languages.freeze
  end

  memoize def detected_codeql_languages
    detected_languages.map(&:downcase).map(&:to_sym).map do |language|
      codeql_language_mapping.key?(language) ? codeql_language_mapping[language] : nil
    end.compact.uniq.sort
  end

  def detected_codeql_languages_string
    detected_codeql_languages.map { |s| "'#{s}'" }.join(", ")
  end

  def detected_codeql_languages_build_mapping
    matrix = {}
    detected_codeql_languages.map(&:to_sym).each do |language|
      matrix[language] = CODEQL_BUILD_MAPPING[language] if CODEQL_BUILD_MAPPING.key?(language)
    end

    # Consider buildless FF
    if matrix[:"java-kotlin"]
      if !detected_languages.map(&:downcase).map(&:to_sym).include?(:kotlin)
        matrix[:"java-kotlin"] = "none # This mode only analyzes Java. Set this to 'autobuild' or 'manual' to analyze Kotlin too."
      end
    end
    matrix
  end

  memoize def supported_codeql_languages_string
    codeql_language_mapping.values.uniq.sort.map { |s| "'#{s}'" }.join(", ")
  end

  def code_scanning_analysis_exists_on_default_ref?
    return false if code_scanning_analyses_response_memoized.blank? || code_scanning_analyses_response_memoized.error.present?

    code_scanning_analyses_response_memoized.data.total_count > 0
  end

  def code_scanning_analyses_response_memoized
    return @code_scanning_analyses_response if defined? @code_scanning_analyses_response
    @code_scanning_analyses_response = GitHub::Turboscan.analyses(
      repository_id: id,
      ref_names_bytes: default_code_scanning_ref_names_bytes,
    )
  end

  def code_scanning_analysis_exists?
    code_scanning_counts_hash_memoized[:analysis_exists]
  end

  # Get the number of open code scanning alerts for this repository's default
  # refs.
  #
  # Returns the open alerts count or -1 if the request fails/errors.
  def code_scanning_open_alerts_count
    code_scanning_counts_hash_memoized[:open_count]
  end

  # Returns the timestamp of the latest analysis, or nil if there is no analysis
  def code_scanning_latest_analysis
    code_scanning_counts_hash_memoized[:latest_analysis]
  end

  def refresh_code_scanning_status(alert_numbers: nil, check_run_ids: nil, refresh_reason: nil)
    # Update the cache count
    analysis_revision.bump unless refresh_reason == :staleness_check

    return if alert_numbers.nil? && check_run_ids.nil?

    check_run_ids ||= ActiveRecord::Base.connected_to(role: :reading) do
      ids = CodeScanningAnnotation.check_run_ids(alert_numbers: alert_numbers, repository: self)
      # Only refresh check runs and annotations associated to the latest commit on open PRs
      check_runs = CheckRun.includes(:check_suite).where(id: ids)
      shas = check_runs.map { |cr| cr.check_suite&.head_sha }.compact.uniq
      pr_shas = PullRequest.includes(:issue).where(head_sha: shas, repository_id: id, issue: { state: "open" }).pluck(:head_sha)
      check_runs.select { |cr| pr_shas.include?(cr.check_suite&.head_sha) }.map(&:id)
    end
    check_run_ids.each_with_index do |check_run_id, _i|
      CreateCodeScanningAnnotationsJob.perform_later(
        check_run_id: check_run_id,
        reason: refresh_reason)
    end
  end

  sig { returns(String) }
  def code_scanning_security_center_scanning_status
    turboscan_considers_code_scanning_enabled? ? "enrolled" : "not_enrolled"
  end

  sig { returns(T.nilable(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus)) }
  def code_scanning_security_center_status
    ownerlocal = owner
    return if ownerlocal.nil?
    return unless ownerlocal.organization?
    return unless ::SecurityCenter::SecurityFeatures.security_center_available?(ownerlocal, dotcom_request_only: true)
    return Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("not_enrolled", 0) unless code_scanning_usable?

    # If the counts are not present, this means the request failed and we do not want to store the result.
    severities = code_scanning_open_alerts_count_by_severity
    return unless severities

    enablement_status = code_scanning_security_center_scanning_status
    return Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new(enablement_status, 0) if enablement_status == "not_enrolled"

    count = severities.values.sum
    severities = nil unless count > 0

    analysis_timestamp = Google::Protobuf::Timestamp.new(code_scanning_latest_analysis).to_time.utc if code_scanning_latest_analysis.present?
    Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new(enablement_status, count, scanning_count_by_severity: severities, scanning_date: analysis_timestamp)
  end

  sig do
    params(code_scanning_status: T.nilable(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus))
    .returns(T.nilable(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus))
  end
  def code_scanning_review_security_center_status(code_scanning_status: nil)
    # prerequisites: code_scanning
    scanning_status = code_scanning_status&.scanning_status || code_scanning_security_center_scanning_status

    T.bind(self, Repository)
    if scanning_status == "enrolled" &&
      (CodeScanning::AutoCodeql.new(self).enabled? || code_scanning_analysis_exists_on_recent_pr?)
      return Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 0)
    end

    Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("not_enrolled", 0)
  end

  sig { returns(T::Boolean) }
  def code_scanning_analysis_exists_on_recent_pr?
    return false unless default_branch_ref.present?

    batch_size = 100
    before = T.let(nil, T.nilable(DateTime))
    loop do
      batch = self.pull_requests.where(base_repository_id: self.id, base_ref: default_branch_ref.name).order("created_at DESC").limit(batch_size)
      batch = batch.where("created_at < ?", before) if before.present?
      batch = batch.preload(:issue)
      batch.each do |pr|
        ref_names = [pr.merge_ref, "refs/pull/#{pr.number}/head".b]
        ref_names << "refs/heads/#{pr.head_ref}".b if id == pr.head_repository_id
        analyses = GitHub::Turboscan.analyses(
          repository_id: id,
          ref_names_bytes: ref_names,
        )
        if analyses.nil? || analyses.error.present?
          err = StandardError.new("Failed to get analyses for PR #{pr.id}: #{analyses&.error}.")
          Failbot.report!(err)
          return false
        end
        return true if T.must(analyses.data).total_count.positive?
        return false if T.must(pr.created_at).before?(PULL_REQUEST_ANALYSIS_TIME_LIMIT.ago) && T.must(analyses.data).total_count.zero?
        before = pr.created_at
      end
      return false if batch.size < batch_size
    end
  end

  sig do
    params(actor: T.nilable(::User))
    .returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus)
  end
  def code_scanning_auto_codeql_security_center_status(actor)
    T.bind(self, Repository)
    auto_codeql = CodeScanning::AutoCodeql.new(self)
    status = if auto_codeql.enabled?
      "enrolled"
    elsif auto_codeql.can_enable?(actor: actor, options: { skip_ghas_check?: true }).value
      "eligible"
    else
      "not_eligible"
    end
    Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new(status, 0)
  end

  memoize def code_scanning_tool_names
    cache_on_not_nil(code_scanning_tools_data_cache_key, stats_prefix: "code_scanning.tool_names_cache") do
      GitHub::Turboscan.tool_names(repository_id: id)
    end || []
  end

  def code_scanning_counts_by_tool
    return @counts if @counts.present?
    res =  cache_on_not_nil(code_scanning_tool_counts_data_cache_key, stats_prefix: "code_scanning.tool_counts_cache") do
      GitHub::Turboscan.counts_by_tool(repository_id: id, ref_names_bytes: default_code_scanning_ref_names_bytes)&.data&.to_h
    end&.deep_symbolize_keys
    @counts = res ? res[:tool_counts] : []
  end

  sig { returns(T.nilable(T::Hash[String, Integer])) }
  memoize def code_scanning_open_alerts_count_by_severity
    request_hash = {
      repository_ids: [id],
      owner_ids: [owner_id],
      filter: Turboscan::Proto::AlertsFilter.new(state: GitHub::Turboscan.to_alert_state_filter("open")).to_h,
    }
    response = GitHub::Turboscan.severities_for_org(Turboscan::Proto::SeveritiesForOrgRequest.new(request_hash).to_h)

    payload = response.try(:data).try(:severities)
    return unless payload

    payload.map { |v| [v.severity.to_s.delete_prefix("SEVERITY_").downcase, v.alert_count] }.to_h
  end

  # Allow a repository to pass any queries to the autofix engine
  # This allow us to test new language and tools support before rolling them out
  def code_scanning_autofix_all_queries_enabled?
    feature_enabled?(:code_scanning_suggested_all_queries, memoize: false)
  end

  # This is an experimental feature we have had for 1+ year so it seems unlikely we'll ship it.
  # See tracking issue: https://github.com/github/code-scanning/issues/11458
  def code_scanning_pr_fixed_alerts_enabled?
    feature_enabled?(:code_scanning_pr_fixed_alerts) || owner&.feature_enabled?(:code_scanning_pr_fixed_alerts)
  end

  def code_scanning_dfa_alert_file_diff_enabled?
    feature_enabled?(:code_scanning_dfa_alert_file_diff) || owner&.feature_enabled?(:code_scanning_dfa_alert_file_diff)
  end

  def code_scanning_check_run_diff_failure_handling_enabled?
    feature_enabled?(:code_scanning_check_run_diff_failure_handling) || owner&.feature_enabled?(:code_scanning_check_run_diff_failure_handling)
  end

  def code_scanning_protected_alert_dismissal_enabled?
    feature_enabled?(:code_scanning_protected_alert_dismissal) || owner&.feature_enabled?(:code_scanning_protected_alert_dismissal)
  end

  def code_scanning_rule_diff_failure_handling_enabled?
    feature_enabled?(:code_scanning_rule_diff_failure_handling) || owner&.feature_enabled?(:code_scanning_rule_diff_failure_handling)
  end

  def code_scanning_autofix_thirdparty_enabled?
    check_enabled_and_disabled_flags?(:code_scanning_autofix_thirdparty, :code_scanning_autofix_thirdparty_disable)
  end

  def code_scanning_cpp_dependency_installation_enabled?
    check_enabled_and_disabled_flags?(:code_scanning_cpp_dependency_installation, :code_scanning_cpp_dependency_installation_disabled)
  end

  def code_scanning_default_codeql_version_2_18_4_enabled?
    check_enabled_and_disabled_flags?(:code_scanning_default_codeql_version_2_18_4, :code_scanning_default_codeql_version_2_18_4_disabled)
  end

  def code_scanning_default_codeql_version_2_19_0_enabled?
    check_enabled_and_disabled_flags?(:code_scanning_default_codeql_version_2_19_0, :code_scanning_default_codeql_version_2_19_0_disabled)
  end

  def code_scanning_default_codeql_version_2_19_1_enabled?
    check_enabled_and_disabled_flags?(:code_scanning_default_codeql_version_2_19_1, :code_scanning_default_codeql_version_2_19_1_disabled)
  end

  def code_scanning_default_codeql_version_2_19_2_enabled?
    check_enabled_and_disabled_flags?(:code_scanning_default_codeql_version_2_19_2, :code_scanning_default_codeql_version_2_19_2_disabled)
  end

  def code_scanning_default_codeql_version_2_19_3_enabled?
    check_enabled_and_disabled_flags?(:code_scanning_default_codeql_version_2_19_3, :code_scanning_default_codeql_version_2_19_3_disabled)
  end

  def code_scanning_default_codeql_version_2_19_4_enabled?
    check_enabled_and_disabled_flags?(:code_scanning_default_codeql_version_2_19_4, :code_scanning_default_codeql_version_2_19_4_disabled)
  end

  def code_scanning_default_codeql_version_2_19_5_enabled?
    check_enabled_and_disabled_flags?(:code_scanning_default_codeql_version_2_19_5, :code_scanning_default_codeql_version_2_19_5_disabled)
  end

  def code_scanning_default_codeql_version_2_19_6_enabled?
    check_enabled_and_disabled_flags?(:code_scanning_default_codeql_version_2_19_6, :code_scanning_default_codeql_version_2_19_6_disabled)
  end

  def code_scanning_disable_java_buildless_enabled?
    check_enabled_and_disabled_flags?(:code_scanning_disable_java_buildless, :code_scanning_disable_java_buildless_disabled)
  end

  def code_scanning_disable_kotlin_analysis_enabled?
    check_enabled_and_disabled_flags?(:code_scanning_disable_kotlin_analysis, :code_scanning_disable_kotlin_analysis_disabled)
  end

  def code_scanning_evaluator_fine_grained_parallelism_enabled?
    check_enabled_and_disabled_flags?(:code_scanning_evaluator_fine_grained_parallelism, :code_scanning_evaluator_fine_grained_parallelism_disabled)
  end

  def code_scanning_export_diagnostics_enabled?
    check_enabled_and_disabled_flags?(:code_scanning_export_diagnostics, :code_scanning_export_diagnostics_disabled)
  end

  def code_scanning_qa_telemetry_enabled?
    check_enabled_and_disabled_flags?(:code_scanning_qa_telemetry, :code_scanning_qa_telemetry_disabled)
  end

  def issues_alerts_integration_enabled?
    return @issues_alerts_integration_enabled if defined?(@issues_alerts_integration_enabled)

    @issues_alerts_integration_enabled = !GitHub.enterprise?
  end

  def code_scanning_action_in_progress_key(ref, commit_oid, category)
    hash = Digest::SHA256.hexdigest("#{id}/#{ref}/#{commit_oid}/#{category}")
    "code_scanning.action_in_progress.#{hash}"
  end

  def store_code_scanning_action_in_progress(ref, commit_oid, category, check_run_id)
    key = code_scanning_action_in_progress_key(ref, commit_oid, category)

    params = { "key": key, "repo_id": id, "ref": ref, "commit_oid": commit_oid, "category": category }
    GitHub.logger.info(
        "code.namespace" => "CodeScanning",
        "code.function" => "action_in_progress::store",
        "gh.repo.id" => id,
        "git.ref" => ref,
        "git.commit.oid" => commit_oid,
        "gh.code_scanning.analysis.category" => category,
        "gh.kv.key" => key,
    )
    GitHub.kv.set(key, "#{check_run_id}", expires: 1.day.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  def code_scanning_action_in_progress(ref, commit_oid, category)
    key = code_scanning_action_in_progress_key(ref, commit_oid, category)

    params = { "key": key, "repo_id": id, "ref": ref, "commit_oid": commit_oid, "category": category }
    GitHub.logger.info(
      "code.namespace" => "CodeScanning",
      "code.function" => "action_in_progress::load",
      "gh.repo.id" => id,
      "git.ref" => ref,
      "git.commit.oid" => commit_oid,
      "gh.code_scanning.analysis.category" => category,
      "gh.kv.key" => key,
  )

    GitHub.kv.get(key).value! # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  def code_scanning_counts_call_failed?
    code_scanning_open_alerts_count < 0
  end

  def check_enabled_and_disabled_flags?(enabled_flag, disabled_flag)
    # There's two feature flags, to allow enabling broadly and then disabling at a tighter scope.
    # Both flags apply at the user/org, repo, and business scopes, and disabling always wins.
    enabled = self.feature_enabled?(enabled_flag, memoize: false) ||
      GitHub.flipper[enabled_flag].enabled?(self.owner) ||
      GitHub.flipper[enabled_flag].enabled?(self.owner&.business)
    disabled = self.feature_enabled?(disabled_flag, memoize: false) ||
      GitHub.flipper[disabled_flag].enabled?(self.owner) ||
      GitHub.flipper[disabled_flag].enabled?(self.owner&.business)
    enabled && !disabled
  end

  def code_scanning_autofix_on_demand_api_enabled?
    feature_enabled?(:code_scanning_autofix_on_demand_api, memoize: false) || owner&.feature_enabled?(:code_scanning_autofix_on_demand_api, memoize: false)
  end

  private

  def code_scanning_counts_hash_memoized
    return @code_scanning_counts_hash if defined? @code_scanning_counts_hash
    @code_scanning_counts_hash = code_scanning_counts_cached
  end

  def code_scanning_counts_cached
    res = cache_on_not_nil(code_scanning_counts_data_cache_key, stats_prefix: "code_scanning.counts_cache") do
      GitHub::Turboscan.counts(
        repository_id: id,
        ref_names_bytes: default_code_scanning_ref_names_bytes,
      )&.data&.to_h
    end&.symbolize_keys

    # -1 is used as a sentinel value for indicating no count
    res || { analysis_exists: false, open_count: -1, latest_analysis: nil }
  end

  def code_scanning_counts_data_cache_key
    branch_hash = Digest::SHA256.hexdigest(default_code_scanning_ref_names_bytes.join("\x00"))
    "turboscan_counts/#{id}/#{branch_hash}/#{analysis_revision.count}"
  end

  def code_scanning_tools_data_cache_key
    "turboscan_tools/#{id}/#{analysis_revision.count}"
  end

  def code_scanning_tool_counts_data_cache_key
    "turboscan_tool_counts/#{id}/#{analysis_revision.count}"
  end

  def cache_on_not_nil(cache_key, stats_prefix: "code_scanning.cache")
    cached_value = GitHub.cache.get(cache_key)
    if cached_value.present?
      v = JSON.parse(cached_value)
      record_cache_stats("#{stats_prefix}.hit", v)
      v
    else
      yield.tap do |v|
        record_cache_stats("#{stats_prefix}.miss", v)
        GitHub.cache.set(cache_key, v.to_json) unless v.nil?
      end
    end
  end

  def record_cache_stats(stats_counter, v)
    missing = v.nil?
    analysis_exists = v.present? && v.is_a?(Hash) && (!!v[:analysis_exists] || !!v["analysis_exists"])
    tags = ["missing:#{missing}", "analysis_exists:#{analysis_exists}"]
    GitHub.dogstats.increment(stats_counter, tags: tags)
  end

  def analysis_revision
    AnalysisRevision.new(id)
  end

  class AnalysisRevision
    def initialize(repo_id)
      @repo_id = repo_id
    end

    def count
      c = GitHub.kv.get(key).value! # rubocop:todo GitHub/DoNotUseGlobalKv
      c.presence || 0
    end

    def bump
      GitHub.kv.increment(key) # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    private

    def key
      "code_scanning/analysis/#{@repo_id}"
    end
  end
end
