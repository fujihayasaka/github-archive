# typed: true
# frozen_string_literal: true
require "test_helper"

class IssueTransfer::CrossReferencesGraphTest < GitHub::TestCase
  setup do
    @owner = create :user, login: "owner", plan: "large"
    @repo = create :private_repository, owner: @owner
    @repo2 = create :private_repository, owner: @owner
  end

  def create_references(source_issue, *target_issues)
    body = target_issues.map do |i|
      if source_issue.repository == i.repository
        "##{i.number}"
      else
        create :cross_reference, source: source_issue, target: i
        nil
      end
    end.compact.join(" ")

    perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) do
      source_issue.body = body
      source_issue.save
    end
  end

  def create_graph
    IssueTransfer::CrossReferencesGraph.from_repo(@repo.id)
  end

  def create_connected_issues
    issues = create_list :issue, 3, repository: @repo, create_references: true

    create_references(issues[0], issues[1])
    create_references(issues[1], issues[0], issues[2])

    issues
  end

  # @repo            @repo2
  # ┌─────────┐     ┌────────┐
  # │ ┌──►0───┼─────┼────►3  │
  # │ │   │   │     │        │
  # │ │   ▼   │     │        │
  # │ └───1◄──┼─────┼──┐     │
  # │     │   │     │  │     │
  # │     ▼   │     │  │     │
  # │     2◄──┼─────┼──┴──4  │
  # └─────────┘     └────────┘
  def create_connected_issues_across_repos
    issues = create_list :issue, 3, repository: @repo, create_references: true
    issues += create_list :issue, 2, repository: @repo2, create_references: true

    create_references(issues[0], issues[1], issues[3])
    create_references(issues[1], issues[0], issues[2])
    create_references(issues[4], issues[1], issues[2])

    issues
  end

  context "empty repo" do
    test "should have an empty graph" do
      graph = create_graph

      assert_equal([], graph.ids)
      assert_equal({}, graph.edges)
    end

    test "should return 0 neighbors" do
      graph = create_graph

      assert_equal false, graph.neighbors?(1)
      assert_equal([], graph.neighbors(1))
      assert_equal([], graph.referencing_neighbors(1))
      assert_equal([], graph.referenced_neighbors(1))
    end
  end

  context "repo with issues, but no cross-references" do
    test "should have an array of ids, but no edges" do
      issues = create_list :issue, 3, repository: @repo, create_references: true
      graph = create_graph

      assert_equal issues.map(&:id), graph.ids
      assert_equal({}, graph.edges)
    end

    test "should return 0 neighbors" do
      issues = create_list :issue, 3, repository: @repo, create_references: true
      graph = create_graph

      id = issues.first.id

      assert_equal false, graph.neighbors?(id)
      assert_equal([], graph.neighbors(id))
      assert_equal([], graph.referencing_neighbors(id))
      assert_equal([], graph.referenced_neighbors(id))
    end
  end

  context "repo with issues and cross-references" do
    test "should return a hash of ids to edges" do
      issues = create_connected_issues
      graph = create_graph

      assert_equal issues.map(&:id), graph.ids
      assert_equal Hash[
        issues[0].id => {
          in: [issues[1].id], out: [issues[1].id]
        },
        issues[1].id => {
          in: [issues[0].id], out: [issues[0].id, issues[2].id]
        },
        issues[2].id => {
          in: [issues[1].id], out: []
        }
      ], graph.edges
    end

    test "should return neighbors" do
      issues = create_connected_issues
      graph = create_graph

      id = issues[1].id

      assert graph.neighbors?(id)
      assert_equal [issues[0].id, issues[2].id], graph.neighbors(id)
      assert_equal [issues[0].id], graph.referencing_neighbors(id)
      assert_equal [issues[0].id, issues[2].id], graph.referenced_neighbors(id)
    end

    test ".neighbors should be uniq" do
      issues = create_connected_issues
      graph = create_graph

      assert_equal [issues[1].id], graph.neighbors(issues[0].id)
    end
  end

  # @repo            @repo2
  # ┌─────────┐     ┌────────┐
  # │ ┌──►0───┼─────┼────►3  │
  # │ │   │   │     │        │
  # │ │   ▼   │     │        │
  # │ └───1◄──┼─────┼──┐     │
  # │     │   │     │  │     │
  # │     ▼   │     │  │     │
  # │     2◄──┼─────┼──┴──4  │
  # └─────────┘     └────────┘
  context "repo with issues and cross-references to another repo" do
    test "should return a hash of ids to edges" do
      issues = create_connected_issues_across_repos
      graph = create_graph

      assert_equal issues[0..2].map(&:id), graph.ids

      assert_equal Hash[
        issues[0].id => {
          in: [issues[1].id], out: [issues[1].id, issues[3].id]
        },
        issues[1].id => {
          in: [issues[0].id, issues[4].id], out: [issues[0].id, issues[2].id]
        },
        issues[2].id => {
          in: [issues[1].id, issues[4].id], out: []
        },
        issues[3].id => {
          in: [issues[0].id], out: []
        },
        issues[4].id => {
          in: [], out: [issues[1].id, issues[2].id]
        }
      ], graph.edges
    end
  end
end
