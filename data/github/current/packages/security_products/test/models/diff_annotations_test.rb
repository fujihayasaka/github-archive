# typed: true
# frozen_string_literal: true

require "test_helper"

class DiffAnnotationsTest < GitHub::TestCase
  setup do
    # This object is mutated by the tests. Do not put in fixtures.
    @diff_annotations = DiffAnnotations.new([
      create(:check_annotation, path: "README.md", end_line: 2),
      create(:check_annotation, path: "README.md", end_line: 3),
      create(:check_annotation, path: "contrib.md", end_line: 2),
    ])
  end

  fixtures do
    user = create(:paid_user)
    @repo = create(:private_repository, owner: user, from_example: :non_diff_annotations)

    # Annotation on modified path
    diff_annotation = create(
      :check_annotation_and_pull_request,
      repository: @repo,
      head_ref: "feature",
      path: "another_file_getting_added_in_branch.py",
    )

    @pull = diff_annotation.check_run.check_suite.matching_pull_requests.first

    # Annotation on non-modified path
    create(
      :check_annotation,
      check_run: diff_annotation.check_run,
      path: "file_exists_in_master.html",
    )

    # Another annotation on non-modified path
    create(
      :check_annotation,
      check_run: diff_annotation.check_run,
      path: "file_also_exists_in_master.js",
    )
  end

  test "retrieves annotations for a path" do
    annotations = @diff_annotations.path("README.md")
    assert_equal 2, annotations.count
  end

  test "returns empty annotations for missing path" do
    annotations = @diff_annotations.path("404")
    assert_equal 0, annotations.count
  end

  test "retrieves annotations at a end_line position" do
    annotations = @diff_annotations.end_line(2)
    assert_equal 2, annotations.count
  end

  test "returns empty annotations for missing line position" do
    annotations = @diff_annotations.end_line(-1)
    assert_equal 0, annotations.count
  end

  test "non_diff_paths returns the appropriate paths" do
    annotations = @repo.annotations_for(sha: @pull.head_sha, limit: CheckAnnotation::MAX_READ_LIMIT)

    pull_comparison = PullRequest::Comparison.find(
      pull: @pull,
      start_commit_oid: @pull.comparison.async_base_oid.sync,
      end_commit_oid:   @pull.comparison.async_head_oid.sync,
      base_commit_oid:  @pull.comparison.async_base_oid.sync,
    )

    diff_annotations = DiffAnnotations.new(annotations, pull_comparison.diffs)

    assert_same_elements(
      ["file_exists_in_master.html", "file_also_exists_in_master.js"],
      diff_annotations.non_diff_paths,
    )
  end

  test "code scanning alerts are not loaded by default" do
    @repo.stubs(:code_scanning_enabled?).returns(true)

    # The alerts haven't been loaded, so code_scanning_alert should return nil
    # and not do any database calls or RPCs.
    CodeScanningAnnotation.expects(:results_by_id).never
    @diff_annotations.each do |annotation|
      assert_nil @diff_annotations.code_scanning_alert(annotation)
    end
  end

  test "code scanning alerts are preserved by path and end_line" do
    @repo.stubs(:code_scanning_enabled?).returns(true)

    annotations = T.let([], T::Array[CheckAnnotation])
    @diff_annotations.each do |a|
      annotations.append(a)
    end

    # Simulate the second annotation in @diff_annotations being an alert
    annotation_ids = annotations.map(&:id)
    alert = annotations[1]
    raise if alert.nil?
    CodeScanningAnnotation.expects(:results_by_id).with(
      repository: @repo,
      annotations: annotation_ids
    ).returns({ alert.id => "fake alert" })

    # Load alerts
    @diff_annotations.load_code_scanning_alerts(viewer: @repo.owner, repository: @repo)

    # Check alert is present
    assert_equal "fake alert", @diff_annotations.code_scanning_alert(alert)
    assert_nil @diff_annotations.code_scanning_alert(annotations[0])

    # Check calling 'path'
    assert_equal "fake alert", @diff_annotations.path("README.md").code_scanning_alert(alert)
    assert_nil @diff_annotations.path("contrib.md").code_scanning_alert(alert)

    # Check calling 'path'
    assert_equal "fake alert", @diff_annotations.end_line(3).code_scanning_alert(alert)
    assert_nil @diff_annotations.end_line(2).code_scanning_alert(alert)
  end

  test "does not exclude annotations without dependabot annotations" do
    filtered_annotations = @diff_annotations.annotations_without_comments(@pull)
    assert_equal 3, filtered_annotations.count, "Annotation without dependabot annotation should not be excluded"
  end
end
