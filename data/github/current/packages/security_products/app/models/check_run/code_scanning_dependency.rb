# typed: true
# frozen_string_literal: true

# Code scanning specific functionality for check runs
module CheckRun::CodeScanningDependency
  CODE_SCANNING_DEFAULT_CHECK_RUN_NAME = "Results"
  RULE_SHORT_DESCRIPTION_LENGTH_LIMIT = 200
  CATEGORIES_LIMIT = 25

  extend T::Helpers

  requires_ancestor { CheckRun }

  class CodeScanningCheckRunError < StandardError
  end

  module ClassMethods
    extend T::Helpers

    include Kernel

    def create_code_scanning_check_suite(repository:, annotated_commit_oid:, analyzed_commit_oid:, ref: nil, base_ref: nil, base_sha: nil)
      check_suite = Checks.domain.check_suites.find_or_create(
        repo: repository,
        head_sha: annotated_commit_oid,
        github_app_id: Apps::Privileged.integration_id(:code_scanning),
      )
      return unless check_suite.present?

      # Ensure that if the check suite does not have branch information, yet, and the upload is for a branch, we set it.
      # This should not actually be necessary, since when creating a cscs we
      # assume that a PR exists. In that case the `ref` will have been pushed with the `annotated_commit_oid` as head
      # and Checks.domain.check_suites.find_or_create will have filled in the `head_branch` from the Push data.
      # But we prefer to double check our assumption.
      if check_suite.head_branch.blank? && ref&.starts_with?("refs/heads/")
        check_suite.update!(head_branch: ref.delete_prefix("refs/heads/"))
      end

      # We only store a pull request ref in the cscs
      pull_request_ref = pull_request_ref_to_store(candidate1: ref)
      # We only store the merge commit sha in the cscs
      pull_request_sha = annotated_commit_oid != analyzed_commit_oid ? analyzed_commit_oid : ""

      code_scanning_check_suite = CodeScanningCheckSuite.retry_on_find_or_create_error do
        # if a CodeScanningCheckSuite is created without CheckSuite knowing about it then it will attempt to create
        # it again later and raise an ActiveRecord::RecordNotUnique error.
        CodeScanningCheckSuite.find_by(check_suite: check_suite, repository: repository) || check_suite.create_code_scanning_check_suite!(
          repository: repository,
          base_ref: base_ref,
          base_sha: base_sha,
          pull_request_ref: pull_request_ref,
          pull_request_sha: pull_request_sha,
        )
      end
      # If we have received an upload for an existing cscs, we might have to update some information.
      pull_request_ref = pull_request_ref_to_store(candidate1: code_scanning_check_suite.pull_request_ref, candidate2: ref)
      if code_scanning_check_suite.pull_request_ref != pull_request_ref || (code_scanning_check_suite.pull_request_sha.empty? && !pull_request_sha.empty?) || (!pull_request_sha.empty? && code_scanning_check_suite.pull_request_sha != pull_request_sha)
        code_scanning_check_suite.update(
          pull_request_ref: pull_request_ref,
          pull_request_sha: pull_request_sha.presence || code_scanning_check_suite.pull_request_sha,
        )
      end

      if check_suite.name.blank?
        check_suite.update(
          name: "Code scanning results",
          check_runs_rerunnable: false,
          rerequestable: false,
        )
      end

      # Update if the base branch has been changed
      if (base_ref && base_ref != code_scanning_check_suite.base_ref) || (base_sha && base_sha != code_scanning_check_suite.base_sha)
        GitHub.logger.info(
          "Updated code scanning check suite with new base info",
          "code.namespace" => "CheckRun",
          "code.function" => "create_for_code_scanning_analysis",
          "gh.repo.id" => repository&.id,
          "gh.check_suite.id" => code_scanning_check_suite.id,
          "gh.pull_request.base_sha.old" => code_scanning_check_suite.base_sha,
          "gh.pull_request.base_sha.new" => base_sha,
          "gh.pull_request.base_ref.old" => code_scanning_check_suite.base_ref,
          "gh.pull_request.base_ref.new" => base_ref,
        )
        code_scanning_check_suite.update(
          base_ref: base_ref,
          base_sha: base_sha,
        )
      end

      code_scanning_check_suite
    end

    def create_code_scanning_check_runs(check_suite:, tool_names: nil)
      check_run_names = if tool_names.present?
        tool_names.map { |name| CodeScanning::Tool.canonical_name(name) }
      else
        # TODO this seems suboptimal, and should probably return early if tool_names is not present
        # (or throw error in order to _require_ tool_names)
        [CODE_SCANNING_DEFAULT_CHECK_RUN_NAME]
      end

      check_runs = check_run_names.uniq.map do |name|
        attrs = {
          name: name,
          repository: check_suite.repository
        }
        CheckRun.retry_on_find_or_create_error do
          check_run = check_suite.check_runs.find_by(attrs)
          unless check_run
            check_run = check_suite.check_runs.create(attrs)
            GitHub.dogstats.increment("code_scanning.check_run.created")
            TrackCodeScanningCheckRunDelayJob.schedule(check_run.id)
          end
          check_run
        end
      end

      check_runs.compact
    end

    # create_for_code_scanning_analysis ensures that annotated_commit_oid has a
    # CheckSuite attached to it with name "Code scanning results" and a CheckRun
    # under that for each entry in tool_names.
    #
    # If there is not already such a CheckSuite created by a previous call, ref,
    # base_ref and base_sha must be provided.
    def create_for_code_scanning_analysis(repository:, annotated_commit_oid:, analyzed_commit_oid:, tool_names: nil, ref: nil, base_ref: nil, base_sha: nil)
      code_scanning_check_suite = create_code_scanning_check_suite(
        repository: repository,
        annotated_commit_oid: annotated_commit_oid,
        analyzed_commit_oid: analyzed_commit_oid,
        ref: ref,
        base_ref: base_ref,
        base_sha: base_sha
      )

      return [] unless code_scanning_check_suite.present?

      create_code_scanning_check_runs(
        check_suite: code_scanning_check_suite.check_suite,
        tool_names: tool_names
      )
    end

    # Match the set of checkruns with the set of tools
    # Tools that do not have a corresponding checkrun get a new one.
    # Checkruns that do not have a corresponding tool are removed.
    sig do
      params(
        check_run_ids: T::Array[Integer],
        tools: T::Array[T::Hash[Symbol, T.any(String, Integer)]],
        repository: Repository,
        annotated_commit_oid: String,
        analyzed_commit_oid: String,
        ref: String
      )
      .returns(T::Array[CheckRun])
    end
    def align_checkruns_with_tools(check_run_ids:, tools:, repository:, annotated_commit_oid:, analyzed_commit_oid:, ref:)
      # We want to use the primary because we might create/delete checkruns.
      check_runs = ActiveRecord::Base.connected_to(role: :writing) do
        CheckRun.where(repository_id: repository.id, id: check_run_ids).load
      end

      check_runs.each do |check_run|
        raise CodeScanningCheckRunError unless check_run.github_app.id == Apps::Privileged.integration_id(:code_scanning)
      end

      t2c = check_runs.index_by { |c| c.name.downcase }

      missing_tool_names = []
      kept_check_runs = []

      # we make sure that we've mapped the returned tool name where appropriate
      mapped_tool_names = tools.map { |t| t[:name] }.map { |name| CodeScanning::Tool.canonical_name(name.to_s) }

      mapped_tool_names.each do |tool_name|
        key = tool_name.to_s.downcase
        if t2c.key?(key)
          # The tool was there, mark it as done by removing it from t2c
          kept_check_runs << t2c.delete(key)
        else
          # the tool doesn't have a checkrun
          missing_tool_names.append(tool_name)
        end
      end

      # CheckRuns that remain in t2c do not have a matching tool, delete them.
      if t2c.values.present?
        GitHub.logger.info(
          "Deleting checkruns with no matching tools in TS analysis.",
          "code.namespace" => "CheckRun",
          "code.function" => "align_checkruns_with_tools",
          "gh.repo.id" => repository.id,
          "gh.check_run.ids" => t2c.values.map(&:id),
          "gh.code_scanning.tools" => t2c.keys,
        )
        t2c.values.each do |check_run|
          check_run.destroy
          GitHub.dogstats.increment("code_scanning.check_run.deleted")
        end
      end

      check_run_ids -= t2c.values.map(&:id)

      # missing tools need to have a CheckRun created and added to the list
      new_check_runs = []
      if missing_tool_names.present?
        new_check_runs = create_for_code_scanning_analysis(
          repository: repository,
          annotated_commit_oid: annotated_commit_oid,
          analyzed_commit_oid: analyzed_commit_oid,
          tool_names: missing_tool_names,
          ref: ref
        )
        GitHub.logger.info(
          "Created missing checkruns for the tools in TS analysis.",
          "code.namespace" => "CheckRun",
          "code.function" => "align_checkruns_with_tools",
          "gh.repo.id" => repository.id,
          "gh.check_run.ids" => new_check_runs.map(&:id),
          "gh.code_scanning.tools" => missing_tool_names,
        )
      end

      kept_check_runs + new_check_runs
    end

    private

    def pull_request_ref_to_store(candidate1:, candidate2: nil)
      # Prefer merge ref above everything, then a PR head ref, never store a branch ref
      return candidate1 if candidate1.starts_with?("refs/pull/") && candidate1.ends_with?("/merge")
      return candidate2 if candidate2&.starts_with?("refs/pull/") && candidate2&.ends_with?("/merge")
      return candidate1 if candidate1.starts_with?("refs/pull/")
      return candidate2 if candidate2&.starts_with?("refs/pull/")
      ""
    end
  end

  mixes_in_class_methods(ClassMethods)

  def code_scanning_tool_name
    if name != CODE_SCANNING_DEFAULT_CHECK_RUN_NAME
      name
    end
  end

  def update_for_code_scanning_diff!(summarizer)
    old_conclusion = conclusion
    self.summary = summarizer.summary.truncate_bytes(65535, omission: "...")
    self.title = summarizer.title
    new_conclusion = summarizer.conclusion

    self.conclusion = new_conclusion
    save!

    if new_conclusion != old_conclusion
      GitHub.dogstats.increment("code_scanning.check_run.count", tags: ["conclusion:#{new_conclusion}"])
    end
  end

end
