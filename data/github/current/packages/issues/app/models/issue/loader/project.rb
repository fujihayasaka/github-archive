# typed: true
# frozen_string_literal: true

class Issue::Loader::Project
  attr_reader :context

  def initialize(issue, repository, viewer, timeline_size: nil, cap_filter: nil)
    @context = Issue::Adapter::Context.new(issue, repository, viewer, cap_filter: cap_filter)
    @timeline_size = timeline_size
    preload
  end

  def self.issue_node(issue, repository, viewer, timeline_size: nil, cap_filter: nil)
    self.issue_adapter(
      new(issue, repository, viewer, timeline_size: timeline_size, cap_filter: cap_filter)
    )
  end

  def self.issue_adapter(loader)
    Issue::Adapter::IssueAdapter.new(
      loader.context,
      skip_timeline: true
    )
  end

  def preload
    preload_repository
    preload_issue

    @context.preload_attr(:integrations_by_model, {})
  end

  def preload_issue
    Issue::Loader::CurrentIssue.load_for(@context)
  end

  def preload_repository
    Issue::Loader::CurrentRepository.load_for(@context)
  end
end
