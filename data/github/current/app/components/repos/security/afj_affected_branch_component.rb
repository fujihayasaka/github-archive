# typed: true
# frozen_string_literal: true

class Repos::Security::AfjAffectedBranchComponent < ApplicationComponent
  # affected_branches should be an array of item from the arrays returned by
  # RepositoryCodeScanning::ShowView.afj_affected_branches
  def initialize(affected_branches:, repository:, more: 0, **system_arguments)
    @affected_branches = affected_branches
    @system_arguments = system_arguments
    @more = more
    @repository = repository
  end

  attr_reader :affected_branches
  attr_reader :more
  attr_reader :repository

  PR_MERGE_COMMIT_REGEX = /\AMerge pull request #(\d+)/

  def all_fixed?(affected_branch_info:)
    affected_branch_info[:configs].all? { |c| c[:is_fixed] }
  end

  def icon(affected_branch_info:)
    return "shield-x" if affected_branch_info[:dismissed?]
    all_fixed?(affected_branch_info: affected_branch_info) ? "shield-check" : "shield"
  end

  def color(affected_branch_info:)
    return :closed if affected_branch_info[:dismissed?]
    all_fixed?(affected_branch_info: affected_branch_info) ? :done : :success
  end

  def num_analysis_origins(affected_branch_info:)
    filtered = affected_branch_info[:configs].select { |c| !c[:is_outdated] }
    # we only count the number of unique categories
    filtered.size
  end

  def show_analysis_origins?(affected_branch_info:)
    num_analysis_origins(affected_branch_info: affected_branch_info) > 1
  end

  def stale_alerts_dialog_id(index:)
    "stale-alerts-dialog-id-#{index + more}"
  end

  def first_created_at(affected_branch_info:)
    if !all_fixed?(affected_branch_info:)
      affected_branch_info[:configs]
        .map { |c| c[:created_at] }
        .select { |t| t.present? }
        .sort
        .first
    else
      nil
    end
  end

  # Given a list of configs for a branch:
  # - find the earliest config
  def earliest_fix_config(affected_branch_info:)
    fixed_configs = affected_branch_info[:configs].select { |c| c[:is_fixed] }
    if fixed_configs.any?
      fixed_configs
        .select { |c| c[:fixed_at].present? }
        .sort_by { |c| c[:fixed_at] }
        .first
    else
      nil
    end
  end

  # TODO: we could likely detect PR merges more accurately, including
  # 'merges' using a rebase strategy, using a combination of
  # `Commit#parent_oids` and `Commit#introductory_pull_request`
  sig { params(fixed_at_oid: String).returns(T.nilable(String)) }
  def fix_location_text(fixed_at_oid)
    fix_commit = begin
      @repository.commits.find(fixed_at_oid)
    rescue GitRPC::ObjectMissing
      nil
    end
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
