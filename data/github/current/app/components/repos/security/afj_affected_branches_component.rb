# typed: true
# frozen_string_literal: true

class Repos::Security::AfjAffectedBranchesComponent < ApplicationComponent

  sig do
    params(
      affected_branches: T::Array[T::Hash[Symbol, T.untyped]],
      repository: Repository,
      more: Integer,
      alert_links: T::Array[CodeScanning::AlertLink],
      system_arguments: T.untyped
    ).void
  end
  def initialize(affected_branches:, repository:, more: 0, alert_links: [], **system_arguments)
    @affected_branches = affected_branches
    @alert_links = alert_links
    @system_arguments = system_arguments
    @more = more
    @repository = repository
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  attr_reader :affected_branches

  sig { returns(Integer) }
  attr_reader :more

  sig { returns(Repository) }
  attr_reader :repository

  PR_MERGE_COMMIT_REGEX = /\AMerge pull request #(\d+)/

  sig { params(affected_branch: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
  def all_fixed?(affected_branch:)
    affected_branch[:configs].all? { |c| c[:is_fixed] }
  end

  sig { params(affected_branch: T::Hash[Symbol, T.untyped]).returns(String) }
  def icon(affected_branch:)
    return "shield-x" if affected_branch[:dismissed?]
    all_fixed?(affected_branch: affected_branch) ? "shield-check" : "shield"
  end

  sig { params(affected_branch: T::Hash[Symbol, T.untyped]).returns(Symbol) }
  def color(affected_branch:)
    return :closed if affected_branch[:dismissed?]
    all_fixed?(affected_branch: affected_branch) ? :done : :success
  end

  sig { params(affected_branch: T::Hash[Symbol, T.untyped]).returns(T.nilable(String)) }
  def description(affected_branch:)
    return nil if affected_branch[:dismissed?]

    unless all_fixed?(affected_branch:)
      introduction_date = first_created_at(affected_branch:)
      pr_text = fixing_pr_text(affected_branch:)
      prefix = pr_text ? "#{pr_text} " : ""
      end_punctuation = prefix.present? ? "." : ""
      return prefix + "First detected #{time_ago_in_words(introduction_date)} ago" + end_punctuation
    end

    last_fixed_config = last_fixed_config_by_branch[affected_branch]
    if last_fixed_config.present?
      fixed_at_oid = last_fixed_config[:fixed_at_oid]
      fix_commit = fix_commits_by_oid[fixed_at_oid]
      "Fixed #{time_ago_in_words(last_fixed_config[:fixed_at])} ago #{fix_location_text(fix_commit, fixed_at_oid)}"
    end
  end

  sig { params(affected_branch: T::Hash[Symbol, T.untyped]).returns(Integer) }
  def num_analysis_origins(affected_branch:)
    filtered = affected_branch[:configs].select { |c| !c[:is_outdated] }
    # we only count the number of unique categories
    filtered.size
  end

  sig { params(affected_branch: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
  def show_analysis_origins?(affected_branch:)
    num_analysis_origins(affected_branch: affected_branch) > 1
  end

  sig { params(index: Integer).returns(String) }
  def stale_alerts_dialog_id(index:)
    "stale-alerts-dialog-id-#{index + more}"
  end

  sig { params(affected_branch: T::Hash[Symbol, T.untyped]).returns(T.nilable(T.any(Time, String))) }
  def first_created_at(affected_branch:)
    if !all_fixed?(affected_branch:)
      affected_branch[:configs]
        .map { |c| c[:created_at] }
        .select { |t| t.present? }
        .sort
        .first
    else
      nil
    end
  end

  sig { params(affected_branch: T::Hash[Symbol, T.untyped]).returns(T.nilable(String)) }
  def fixing_pr_text(affected_branch:)
    pr_alert_links = @alert_links.filter { |link| link.pull_request&.base_ref == affected_branch[:name] && link.pull_request&.state == :open }
      .sort_by { |link| link.pull_request&.updated_at }
      .reverse

    if pr_alert_links.length > 1
      GitHub.logger.info(
        "Found multiple pull requests for fixing alert in the same branch",
        "gh.branch.name": affected_branch[:name],
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.repo.id": @repository.id,
        "gh.pull_request.ids": pr_alert_links.map { |link| link.pull_request&.id }.join(","),
        "gh.pull_request.numbers": pr_alert_links.map { |link| link.pull_request&.number }.join(","),
      )
    end

    fixing_pr = pr_alert_links.first&.pull_request
    return unless fixing_pr.present?

    "Merging pull request ##{fixing_pr.number} may fix the alert in this branch."
  end

  sig { returns(T::Hash[T::Hash[Symbol, T.untyped], T.untyped]) }
  memoize def last_fixed_config_by_branch
    @affected_branches.each_with_object({}) do |affected_branch, result|
      if all_fixed?(affected_branch:)
        last_fixed_config = affected_branch[:configs]
          .select { |c| c[:fixed_at].present? }
          .sort_by { |c| c[:fixed_at] }
          .last
        result[affected_branch] = last_fixed_config unless last_fixed_config.nil?
      end
    end
  end

  sig { returns(T::Hash[String, Commit]) }
  memoize def fix_commits_by_oid
    all_fixed_at_oids = last_fixed_config_by_branch.values.map do |config|
      config[:fixed_at_oid]
    end.compact

    return {} if all_fixed_at_oids.blank?

    begin
      @repository.commits.find(all_fixed_at_oids)
    rescue GitRPC::ObjectMissing
      []
    end.index_by(&:oid)
  end

  # See https://github.com/github/code-scanning/issues/17986
  # We could likely detect PR merges more accurately, including
  # 'merges' using a rebase strategy, using a combination of
  # `Commit#parent_oids` and `Commit#introductory_pull_request`
  sig { params(fix_commit: T.nilable(Commit), fixed_at_oid: String).returns(T.nilable(String)) }
  def fix_location_text(fix_commit, fixed_at_oid)
    # if the commit is a merge commit, try to determine if it is a PR merge
    # using the commit message
    if fix_commit&.merge_commit?
      pr_number_match = PR_MERGE_COMMIT_REGEX.match(fix_commit.message_text)
      if pr_number_match
        return "via pull request ##{pr_number_match[1]}"
      end
    end
    # fall back on just showing the commit hash
    "via commit #{fixed_at_oid.first(7)}"
  end
end
