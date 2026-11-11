# typed: true
# frozen_string_literal: true

class StepGroup
  attr_reader :name, :order

  def initialize(name, order)
    @name = name
    @order = order
  end

  REPO_CLONING = StepGroup.new("repo-cloning", 0)
  REPO_CONFIG  = StepGroup.new("config", 1)
  WORKFLOW_RUN = StepGroup.new("workflow-run", 2)
  STACK_CLEANUP = StepGroup.new("stack-cleanup", 3)

  def self.repo_cloning
    REPO_CLONING
  end

  def self.repo_config
    REPO_CONFIG
  end

  def self.workflow_run
    WORKFLOW_RUN
  end

  def self.stack_cleanup
    STACK_CLEANUP
  end
end
