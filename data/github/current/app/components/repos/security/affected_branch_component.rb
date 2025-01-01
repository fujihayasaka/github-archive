# typed: true
# frozen_string_literal: true

class Repos::Security::AffectedBranchComponent < ApplicationComponent
  # affected_branches should be an array of item from the arrays returned by
  # RepositoryCodeScanning::ShowView.affected_branches
  def initialize(affected_branches:, more: 0, **system_arguments)
    @affected_branches = affected_branches
    @system_arguments = system_arguments
    @more = more
  end

  attr_reader :affected_branches
  attr_reader :more

  def all_fixed?(affected_branch_info:)
    affected_branch_info[:instances].all? { |i| i[:is_fixed] }
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
    filtered = affected_branch_info[:instances].select { |i| !i[:is_outdated] }
    # we only count the number of unique categories
    filtered.size
  end

  def show_analysis_origins?(affected_branch_info:)
    num_analysis_origins(affected_branch_info: affected_branch_info) > 1
  end

  def stale_alerts_dialog_id(index:)
    "stale-alerts-dialog-id-#{index + more}"
  end
end
