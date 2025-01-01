# typed: true
# frozen_string_literal: true

module TrackingBlocks
  class Issue
    attr_reader :issue
    attr_reader :uuid

    def initialize(issue:, uuid: nil)
      @issue = issue
      @uuid = uuid
    end

    def to_hierarchy_model
      model = issue.to_hierarchy_model
      model[:key][:primaryKey] = IssuesGraph::Proto::PrimaryKey.new(uuid: @uuid) if @uuid
      model
    end

    def ==(other)
      issue == other.issue
    end
  end
end
