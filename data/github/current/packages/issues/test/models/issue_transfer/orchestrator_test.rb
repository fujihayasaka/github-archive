# typed: true
# frozen_string_literal: true
require "test_helper"

# usefull debugging logger hack:
#   logger = Rails.logger = Logger.new STDOUT
#   logger.level = :info

class IssueTransfer::OrchestratorTest < GitHub::TestCase
  setup do
    @owner = create :user, login: "owner", plan: "large"
    @old_repo = create :private_repository, owner: @owner, name: "old_repo"
    @new_repo = create :private_repository, owner: @owner, name: "new_repo"
  end

  context "batch creation and completion" do
    [{
      name: "No cross references",
      ids: [1, 2, 3],
      edges: {},
      batch_size: 1,
      expected_batches: [[1], [2], [3]]
    },
    {
      name: "2<=1<=3",
      ids: [1, 2, 3],
      edges: { 1 => { in: [3], out: [2] }, 2 => { in: [1], out: [] }, 3 => { in: [], out: [1] } },
      batch_size: 2,
      expected_batches: [[1], [2, 3]]
    },
    {
      name: "3<=2=>1",
      ids: [1, 2, 3],
      edges: { 1 => { in: [2], out: [] }, 2 => { in: [], out: [1, 3] }, 3 => { in: [2], out: [] } },
      batch_size: 2,
      expected_batches: [[1], [2], [3]]
    },
    {
      name: "a circle 1=>2=>3=>1",
      ids: [1, 2, 3],
      edges: { 1 => { in: [3], out: [2] }, 2 => { in: [1], out: [3] }, 3 => { in: [2], out: [1] } },
      batch_size: 2,
      expected_batches: [[1], [2], [3]]
    },

    #    1           5◄───┐
    #    │           │    │
    # ┌──┼──┐     ┌──┼──┐ │
    # │  │  │     │  │  │ │
    # ▼  ▼  ▼     ▼  ▼  ▼ │
    # 2  3◄─4     6  7◄─8─┘
    {
      name: "Two partitions of interconnected issues",
      ids: [1, 2, 3, 4, 5, 6, 7, 8],
      edges: { 1 => { in: [], out: [2, 3, 4] }, 2 => { in: [1], out: [] }, 3 => { in: [4], out: [] }, 4 => { in: [1], out: [3] }, 5 => { in: [8], out: [6, 7, 8] }, 6 => { in: [5], out: [] }, 7 => { in: [5], out: [] }, 8 => { in: [5], out: [5] } },
      batch_size: 3,
      expected_batches: [[1, 5], [2, 6], [3, 7], [4, 8]]
    },

    #    1           5◄───┐
    #    │           │    │     9   10  11
    # ┌──┼──┐     ┌──┼──┐ │
    # │  │  │     │  │  │ │     12  13  14
    # ▼  ▼  ▼     ▼  ▼  ▼ │
    # 2  3◄─4     6  7◄─8─┘
    {
      name: "Two partitions of interconnected issues and a bunch of isolated issues",
      ids: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14],
      edges: { 1 => { in: [], out: [2, 3, 4] }, 2 => { in: [1], out: [] }, 3 => { in: [4], out: [] }, 4 => { in: [1], out: [3] }, 5 => { in: [8], out: [6, 7, 8] }, 6 => { in: [5], out: [] }, 7 => { in: [5], out: [] }, 8 => { in: [5], out: [5] }, 9 => { in: [], out: [] }, 10 => { in: [], out: [] }, 11 => { in: [], out: [] }, 12 => { in: [], out: [] }, 13 => { in: [], out: [] }, 14 => { in: [], out: [] } },
      batch_size: 3,
      expected_batches: [[1, 5, 9], [2, 6, 10], [3, 7, 11], [4, 8, 12], [13, 14]]
    }].each do |test_case|
      test test_case[:name] do
        graph = IssueTransfer::CrossReferencesGraph.new(test_case[:ids], test_case[:edges])

        IssueTransfer::CrossReferencesGraph.stubs(:from_repo).returns(graph)

        orchestrator = IssueTransfer::Orchestrator.new(@old_repo, @new_repo, @owner, {
          batch_size: test_case[:batch_size],
          max_replication_lag: 0
        })

        batches = []

        while !orchestrator.finished?
          batch = orchestrator.create_batch
          batches << batch
          orchestrator.complete_batch(batch)
        end

        assert_equal test_case[:expected_batches], batches.map { |b| b.issue_ids }
      end
    end

    test "cross references across repositories" do
      ids = [1, 2, 3]
      edges = { 1 => { in: [4], out: [] }, 2 => { in: [4], out: [] }, 3 => { in: [4], out: [] }, 4 => { in: [], out: [1, 2, 3] } }
      graph = IssueTransfer::CrossReferencesGraph.new(ids, edges)

      IssueTransfer::CrossReferencesGraph.stubs(:from_repo).returns(graph)

      orchestrator = IssueTransfer::Orchestrator.new(@old_repo, @new_repo, @owner, {
        batch_size: 3,
        max_replication_lag: 0
      })

      batches = []

      while !orchestrator.finished?
        batch = orchestrator.create_batch
        batches << batch
        orchestrator.complete_batch(batch)
      end

      assert_equal [[1], [2], [3]], batches.map { |b| b.issue_ids }
    end
  end

  context "issue transfer" do
    test "No cross references" do
      10.times do |i|
        create :issue, repository: @old_repo, number: i + 1
      end

      orchestrator = IssueTransfer::Orchestrator.new(@old_repo, @new_repo, @owner, {
        batch_size: 2,
        max_replication_lag: 0
      })

      perform_enqueued_jobs only: TransferIssueJob do
        orchestrator.transfer_issues!
      end

      assert_equal 10, @new_repo.issues.count
    end

    test "2<=1<=3" do
      issue_1 = create :issue, repository: @old_repo, number: 1
      issue_2 = create :issue, repository: @old_repo, number: 2
      issue_3 = create :issue, repository: @old_repo, number: 3

      issue_3.body = "#1"
      issue_3.save!
      issue_1.create_comment(@owner, "#2")

      orchestrator = IssueTransfer::Orchestrator.new(@old_repo, @new_repo, @owner, {
        batch_size: 10,
        max_replication_lag: 0
      })

      perform_enqueued_jobs only: TransferIssueJob do
        orchestrator.transfer_issues!
      end

      assert_equal 3, @new_repo.issues.count

      issue_1_new = T.must(IssueTransfer.find_by!(old_issue_id: issue_1.id).new_issue)
      issue_2_new = T.must(IssueTransfer.find_by!(old_issue_id: issue_2.id).new_issue)
      issue_3_new = T.must(IssueTransfer.find_by!(old_issue_id: issue_3.id).new_issue)

      assert_equal 1, issue_1_new.comments.count
      assert_equal "#{@owner}/#{@new_repo.name}##{issue_2_new.number}", T.must(issue_1_new.comments.first).body
      assert_equal "#{@owner}/#{@new_repo.name}##{issue_1_new.number}", issue_3_new.body

      assert_equal 1, issue_1_new.references.size
      assert_equal 1, issue_2_new.references.size
    end

    test "3<=2=>1" do
      issue_1 = create :issue, repository: @old_repo, number: 1
      issue_2 = create :issue, repository: @old_repo, number: 2
      issue_3 = create :issue, repository: @old_repo, number: 3

      issue_2.create_comment(@owner, "#1 #3")

      orchestrator = IssueTransfer::Orchestrator.new(@old_repo, @new_repo, @owner, {
        batch_size: 10,
        max_replication_lag: 0
      })

      perform_enqueued_jobs only: TransferIssueJob do
        orchestrator.transfer_issues!
      end

      assert_equal 3, @new_repo.issues.count

      issue_1_new = T.must(IssueTransfer.find_by!(old_issue_id: issue_1.id).new_issue)
      issue_2_new = T.must(IssueTransfer.find_by!(old_issue_id: issue_2.id).new_issue)
      issue_3_new = T.must(IssueTransfer.find_by!(old_issue_id: issue_3.id).new_issue)

      # assert_equal "#1 #3", issue_2_new.comments.first.body
      assert_equal 1, issue_1_new.references.size
      assert_equal 1, issue_3_new.references.size

      assert_equal "#{@new_repo.nwo}##{issue_1_new.number} #{@new_repo.nwo}##{issue_3_new.number}", T.must(issue_2_new.comments.first).body
    end

    test "1=>2=>3=>1" do
      issue_1 = create :issue, repository: @old_repo, number: 1
      issue_2 = create :issue, repository: @old_repo, number: 2
      issue_3 = create :issue, repository: @old_repo, number: 3

      issue_1.create_comment(@owner, "#2")
      issue_2.create_comment(@owner, "#3")
      issue_3.create_comment(@owner, "#1")

      orchestrator = IssueTransfer::Orchestrator.new(@old_repo, @new_repo, @owner, {
        batch_size: 10,
        max_replication_lag: 0
      })

      perform_enqueued_jobs only: TransferIssueJob do
        orchestrator.transfer_issues!
      end

      assert_equal 3, @new_repo.issues.count

      issue_1_new = T.must(IssueTransfer.find_by!(old_issue_id: issue_1.id).new_issue)
      issue_2_new = T.must(IssueTransfer.find_by!(old_issue_id: issue_2.id).new_issue)
      issue_3_new = T.must(IssueTransfer.find_by!(old_issue_id: issue_3.id).new_issue)

      assert_equal "#{@new_repo.nwo}##{issue_2_new.number}", T.must(issue_1_new.comments.first).body
      assert_equal "#{@new_repo.nwo}##{issue_3_new.number}", T.must(issue_2_new.comments.first).body
      assert_equal "#{@new_repo.nwo}##{issue_1_new.number}", T.must(issue_3_new.comments.first).body
    end

    #    1           5◄───┐
    #    │           │    │     9   10  11
    # ┌──┼──┐     ┌──┼──┐ │
    # │  │  │     │  │  │ │     12  13  14
    # ▼  ▼  ▼     ▼  ▼  ▼ │
    # 2  3◄─4     6  7◄─8─┘
    test "Two partitions of interconnected issues and a bunch of isolated issues" do
      issue_1 = create :issue, repository: @old_repo, number: 1
      issue_2 = create :issue, repository: @old_repo, number: 2
      issue_3 = create :issue, repository: @old_repo, number: 3
      issue_4 = create :issue, repository: @old_repo, number: 4
      issue_5 = create :issue, repository: @old_repo, number: 5
      issue_6 = create :issue, repository: @old_repo, number: 6
      issue_7 = create :issue, repository: @old_repo, number: 7
      issue_8 = create :issue, repository: @old_repo, number: 8
      issue_9 = create :issue, repository: @old_repo, number: 9
      issue_10 = create :issue, repository: @old_repo, number: 10
      issue_11 = create :issue, repository: @old_repo, number: 11
      issue_12 = create :issue, repository: @old_repo, number: 12
      issue_13 = create :issue, repository: @old_repo, number: 13
      issue_14 = create :issue, repository: @old_repo, number: 14

      # Partition 1
      issue_1.create_comment(@owner, "#2")
      issue_1.create_comment(@owner, "#3")
      issue_1.create_comment(@owner, "#4")
      issue_4.create_comment(@owner, "#3")

      #Partition 2
      issue_5.create_comment(@owner, "#6")
      issue_5.create_comment(@owner, "#7")
      issue_5.create_comment(@owner, "#8")
      issue_8.create_comment(@owner, "#7")
      issue_8.create_comment(@owner, "#5")

      orchestrator = IssueTransfer::Orchestrator.new(@old_repo, @new_repo, @owner, {
        batch_size: 3,
        max_replication_lag: 0
      })

      perform_enqueued_jobs only: TransferIssueJob do
        orchestrator.transfer_issues!
      end

      assert_equal 14, @new_repo.issues.count

      issue_1_new = T.must(IssueTransfer.find_by!(old_issue_id: issue_1.id).new_issue)
      issue_2_new = T.must(IssueTransfer.find_by!(old_issue_id: issue_2.id).new_issue)
      issue_3_new = T.must(IssueTransfer.find_by!(old_issue_id: issue_3.id).new_issue)
      issue_4_new = T.must(IssueTransfer.find_by!(old_issue_id: issue_4.id).new_issue)
      issue_5_new = T.must(IssueTransfer.find_by!(old_issue_id: issue_5.id).new_issue)
      issue_6_new = T.must(IssueTransfer.find_by!(old_issue_id: issue_6.id).new_issue)
      issue_7_new = T.must(IssueTransfer.find_by!(old_issue_id: issue_7.id).new_issue)
      issue_8_new = T.must(IssueTransfer.find_by!(old_issue_id: issue_8.id).new_issue)

      assert_equal "#{@new_repo.nwo}##{issue_2_new.number}", issue_1_new.comments[0].body
      assert_equal "#{@new_repo.nwo}##{issue_3_new.number}", issue_1_new.comments[1].body
      assert_equal "#{@new_repo.nwo}##{issue_4_new.number}", issue_1_new.comments[2].body
      assert_equal "#{@new_repo.nwo}##{issue_3_new.number}", issue_4_new.comments[0].body

      assert_equal "#{@new_repo.nwo}##{issue_6_new.number}", issue_5_new.comments[0].body
      assert_equal "#{@new_repo.nwo}##{issue_7_new.number}", issue_5_new.comments[1].body
      assert_equal "#{@new_repo.nwo}##{issue_8_new.number}", issue_5_new.comments[2].body
      assert_equal "#{@new_repo.nwo}##{issue_7_new.number}", issue_8_new.comments[0].body
      assert_equal "#{@new_repo.nwo}##{issue_5_new.number}", issue_8_new.comments[1].body
    end

    test "cross-references in issue bodies sample 1" do # 14 -> 2 <- 1
      # see https://github.com/github/issues/issues/2543#issuecomment-1125969832
      issue_14 = create :issue, repository: @old_repo, number: 14
      issue_2 = create :issue, repository: @old_repo, number: 2
      issue_1 = create :issue, repository: @old_repo, number: 1

      issue_14.update!(body: "hello \n #2")
      issue_2.update!(body: "hello \n #1")
      issue_1.update!(body: "hello \n #2")

      orchestrator = IssueTransfer::Orchestrator.new(@old_repo, @new_repo, @owner, {
        batch_size: 10,
        max_replication_lag: 0
      })

      perform_enqueued_jobs only: TransferIssueJob do
        orchestrator.transfer_issues!
      end

      assert_equal 3, @new_repo.issues.count

      issue_1_new = T.must(IssueTransfer.find_by!(old_issue_id: issue_1.id).new_issue)
      issue_2_new = T.must(IssueTransfer.find_by!(old_issue_id: issue_2.id).new_issue)
      issue_14_new = T.must(IssueTransfer.find_by!(old_issue_id: issue_14.id).new_issue)

      assert_equal 1, issue_1_new.references.size
      assert_equal 2, issue_2_new.references.size
      assert_equal 0, issue_14_new.references.size

      assert_equal "hello \n #{@new_repo.nwo}##{issue_2_new.number}", issue_1_new.body
      assert_equal "hello \n #{@new_repo.nwo}##{issue_1_new.number}", issue_2_new.body
      assert_equal "hello \n #{@new_repo.nwo}##{issue_2_new.number}", issue_14_new.body
    end

    test "cross-references in issue bodies sample 2" do # 14 -> 2 <- 1
      # see https://github.com/github/issues/issues/2543#issuecomment-1125969832
      issue_1 = create :issue, repository: @old_repo, number: 1
      issue_2 = create :issue, repository: @old_repo, number: 2
      issue_14 = create :issue, repository: @old_repo, number: 14

      issue_14.update!(body: "hello \n #2")
      issue_2.update!(body: "hello \n #1")
      issue_1.update!(body: "hello \n #2")

      orchestrator = IssueTransfer::Orchestrator.new(@old_repo, @new_repo, @owner, {
        batch_size: 10,
        max_replication_lag: 0
      })

      perform_enqueued_jobs only: TransferIssueJob do
        orchestrator.transfer_issues!
      end

      assert_equal 3, @new_repo.issues.count

      issue_1_new = T.must(IssueTransfer.find_by!(old_issue_id: issue_1.id).new_issue)
      issue_2_new = T.must(IssueTransfer.find_by!(old_issue_id: issue_2.id).new_issue)
      issue_14_new = T.must(IssueTransfer.find_by!(old_issue_id: issue_14.id).new_issue)

      assert_equal 1, issue_1_new.references.size
      assert_equal 2, issue_2_new.references.size
      assert_equal 0, issue_14_new.references.size

      assert_equal "hello \n #{@new_repo.nwo}##{issue_2_new.number}", issue_1_new.body
      assert_equal "hello \n #{@new_repo.nwo}##{issue_1_new.number}", issue_2_new.body
      assert_equal "hello \n #{@new_repo.nwo}##{issue_2_new.number}", issue_14_new.body
    end
  end unless ENV["GITHUB_CI"]

  context "restarting" do
    test "does not create duplicate issue for existing transfer" do
      issue_1 = create :issue, repository: @old_repo, number: 1
      orchestrator = IssueTransfer::Orchestrator.new(@old_repo, @new_repo, @owner)

      # simulate partial transfer
      orchestrator.send(:create_all_transfers!)

      # execute the transfer again
      perform_enqueued_jobs only: TransferIssueJob do
        orchestrator.transfer_issues!
      end

      assert_equal 1, @new_repo.issues.count
    end

    test "completes existing transfers" do
      issue_1 = create :issue, repository: @old_repo, number: 1
      orchestrator = IssueTransfer::Orchestrator.new(@old_repo, @new_repo, @owner)

      # simulate partial transfer
      orchestrator.send(:create_all_transfers!)

      transfer = IssueTransfer.where(old_repository: @old_repo).first
      assert_equal("started", T.must(transfer).state)

      # execute the transfer again
      perform_enqueued_jobs only: TransferIssueJob do
        orchestrator.transfer_issues!
      end

      assert_equal("done", T.must(transfer).reload.state)
    end
  end
end
