# typed: true
# frozen_string_literal: true

class Issues::References::BranchComponent < ApplicationComponent
  attr_reader :branch, :checked, :branch_name

  def render?
    !@branch.nil?
  end

  # branch: Git::Ref
  #  The branch to link or not link to issue
  # checked: Boolean
  #   True if the branch is linked to the issue
  def initialize(branch:, checked: false)
    @branch = branch
    @checked = checked
    @branch_name = branch.name_for_display if branch
  end
end
