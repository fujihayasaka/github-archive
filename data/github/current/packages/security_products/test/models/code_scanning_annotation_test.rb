# typed: true
# frozen_string_literal: true

require "test_helper"

class CodeScanningAnnotationTest < GitHub::TestCase
  DataMock = Struct.new(:result, :results, :number)
  fixtures do
    @cs_annotation = create(:code_scanning_annotation)
  end

  test "is deleted after check annotation destruction" do
    assert_difference('CodeScanningAnnotation.annotate("cross-shard-query-exempted").count', -1) do
      @cs_annotation.check_annotation.destroy
    end
  end

  test "is deleted after repository soft-deletion" do
    repo = @cs_annotation.check_annotation.check_run.repository

    assert_difference('CodeScanningAnnotation.annotate("cross-shard-query-exempted").count', -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        repo.remove(repo.owner, synchronous: true)
      end
    end
  end

  context "#results_by_id" do
    test "results_by_id produces correct pull_request_refs for branchname" do
      check_annotation = create(:check_annotation)
      check_run = check_annotation.check_run
      cs_annotation = create(:code_scanning_annotation, check_annotation: check_annotation, alert_number: 1)
      create(:code_scanning_check_suite, check_suite: check_run.check_suite)

      # stub annotations response
      response = Twirp::ClientResp.new(data: DataMock.new(results: [DataMock.new(result: DataMock.new(number: cs_annotation.alert_number))]))
      GitHub::Turboscan.expects(:annotations).returns(response)

      results = CodeScanningAnnotation.results_by_id(repository: check_run.repository, annotations: [check_annotation])

      assert_equal(["refs/heads/master"], results[cs_annotation.check_annotation_id][:pull_request_refs])
    end

    test "results_by_id produces correct pull_request_refs for PR head ref" do
      check_annotation = create(:check_annotation)
      check_run = check_annotation.check_run
      cs_annotation = create(:code_scanning_annotation, check_annotation: check_annotation, alert_number: 1)
      create(:code_scanning_check_suite, check_suite: check_run.check_suite, pull_request_ref: "refs/pull/1/head")

      # stub annotations response
      response = Twirp::ClientResp.new(data: DataMock.new(results: [DataMock.new(result: DataMock.new(number: cs_annotation.alert_number))]))
      GitHub::Turboscan.expects(:annotations).with(
        repository_id: check_annotation.repository.id,
        numbers: [1],
        head_commit_oid: check_run.check_suite.head_sha,
        merge_commit_oid: nil,
      ).returns(response)

      results = CodeScanningAnnotation.results_by_id(repository: check_run.repository, annotations: [check_annotation])

      assert_equal(["refs/pull/1/head", "refs/heads/master"], results[cs_annotation.check_annotation_id][:pull_request_refs])
    end

    test "results_by_id produces correct pull_request_refs for PR merge ref" do
      check_annotation = create(:check_annotation)
      check_run = check_annotation.check_run
      cs_annotation = create(:code_scanning_annotation, check_annotation: check_annotation, alert_number: 1)
      example_repo(:rebase_pull_request, check_annotation.repository)

      pull = create(:pull_request,
        repository: check_annotation.repository,
        base_repository: check_annotation.repository,
        base_user: check_annotation.repository.owner,
        base_ref: "master",
        head_repository: check_annotation.repository,
        head_user: check_annotation.repository.owner,
        head_ref: "contrib",
      )
      merge_commit_sha = pull.create_merge_commit
      create(:code_scanning_check_suite, check_suite: check_run.check_suite, pull_request_ref: pull.merge_ref, pull_request_sha: merge_commit_sha)

      # stub annotations response
      response = Twirp::ClientResp.new(data: DataMock.new(results: [DataMock.new(result: DataMock.new(number: cs_annotation.alert_number))]))
      GitHub::Turboscan.expects(:annotations).with(
        repository_id: check_annotation.repository.id,
        numbers: [1],
        head_commit_oid: check_run.check_suite.head_sha,
        merge_commit_oid: merge_commit_sha,
      ).returns(response)

      results = CodeScanningAnnotation.results_by_id(repository: check_run.repository, annotations: [check_annotation])

      assert_equal(["refs/pull/1/merge", "refs/pull/1/head", "refs/heads/master"], results[cs_annotation.check_annotation_id][:pull_request_refs])
    end

    test "results_by_id handles a nil check_run.head_branch gracefully" do
      check_annotation = create(:check_annotation)
      check_run = check_annotation.check_run
      cs_annotation = create(:code_scanning_annotation, check_annotation: check_annotation, alert_number: 1)
      cs_check_suite = create(:code_scanning_check_suite, check_suite: check_run.check_suite, pull_request_ref: "refs/pull/1/merge")

      cs_check_suite.check_suite.head_branch = nil
      cs_check_suite.check_suite.save

      # stub annotations response
      response = Twirp::ClientResp.new(data: DataMock.new(results: [DataMock.new(result: DataMock.new(number: cs_annotation.alert_number))]))
      GitHub::Turboscan.expects(:annotations).returns(response)

      results = CodeScanningAnnotation.results_by_id(repository: check_run.repository, annotations: [check_annotation])

      assert_equal(["refs/pull/1/merge", "refs/pull/1/head"], results[cs_annotation.check_annotation_id][:pull_request_refs])
    end

    test "results_by_id skips the turboscan call when we can't find a suitable head or merge commit oid" do
      check_annotation1 = create(:check_annotation)
      check_run1 = check_annotation1.check_run
      cs_annotation1 = create(:code_scanning_annotation, check_annotation: check_annotation1, alert_number: 1)

      CodeScanningAnnotation.expects(:analysis_commit_oid).at_least_once.returns(nil)
      GitHub::Turboscan.expects(:annotations).never

      CodeScanningAnnotation.results_by_id(repository: check_run1.repository, annotations: [check_annotation1])
    end
  end


  context "#check_run_ids" do
    test "returns all check run ids associated with alert numbers and repository" do
      check_annotation1 = create(:check_annotation)
      check_run1 = check_annotation1.check_run
      check_annotation2 = create(:check_annotation, check_run: check_run1)
      check_annotation3 = create(:check_annotation)
      check_run2 = check_annotation3.check_run
      cs_annotation1 = create(:code_scanning_annotation, check_annotation: check_annotation1, alert_number: 1)
      cs_annotation2 = create(:code_scanning_annotation, check_annotation: check_annotation2, alert_number: 2)
      cs_annotation3 = create(:code_scanning_annotation, check_annotation: check_annotation3, alert_number: 1)

      assert_equal [], CodeScanningAnnotation.check_run_ids(alert_numbers: [3], repository: check_run1.repository)
      assert_equal [check_run1.id], CodeScanningAnnotation.check_run_ids(alert_numbers: [2], repository: check_run1.repository)
      assert_equal [check_run1.id], CodeScanningAnnotation.check_run_ids(alert_numbers: [1, 2], repository: check_run1.repository)

      assert_equal [], CodeScanningAnnotation.check_run_ids(alert_numbers: [3], repository: check_run2.repository)
      assert_equal [], CodeScanningAnnotation.check_run_ids(alert_numbers: [2], repository: check_run2.repository)
      assert_equal [check_run2.id], CodeScanningAnnotation.check_run_ids(alert_numbers: [1, 2], repository: check_run2.repository)
    end
  end
end
