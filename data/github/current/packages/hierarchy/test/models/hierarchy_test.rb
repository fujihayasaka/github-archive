# typed: true
# frozen_string_literal: true

require "test_helper"

class HierarchyTest < GitHub::TestCase
  include IssuesGraphTestHelpers

  context "when passed in real data" do
    test "#tasklist_blocks returns an array of tasklist blocks" do
      tracking = build_proto_tasklist_block
      issue = build_proto_issue
      data = Struct.new(:tracking, :issue).new([tracking], issue)
      raw = IssuesGraph::Result.new(data: data)

      result = Hierarchy.new(raw).tasklist_blocks
      refute_empty result
    end

    test "#issue returns hierarchy data for the issue" do
      tracking = build_proto_tasklist_block
      issue = build_proto_issue
      data = Struct.new(:tracking, :issue).new([tracking], issue)
      raw = IssuesGraph::Result.new(data: data)

      result = Hierarchy.new(raw).issue
      refute_nil result
    end

    test "#completion returns hierarchy data for the issue's completion" do
      tracking = build_proto_tasklist_block
      issue = build_proto_issue
      data = Struct.new(:tracking, :issue).new([tracking], issue)
      raw = IssuesGraph::Result.new(data: data)

      result = Hierarchy.new(raw).completion
      refute_nil result
    end
  end
end
