# frozen_string_literal: true

require "test_helper"

class ChatopsControllerTest < ActionController::TestCase
  include ActiveJob::TestHelper
  include ChatopsController::TestCaseHelpers

  def chatop_success?
    response.successful? &&
      response.parsed_body["error"].blank?
  end

  def assert_chatop_success
    assert chatop_success?
  end

  def chatop_failure?
    !response.successful? &&
      response.parsed_body["error"].present?
  end

  def assert_chatop_failure
    assert chatop_failure?
  end

  setup do
    chatops_prefix "ghsa"
    chatops_auth!

    assert_enqueued_jobs 0
  end

  # .ghsa import tests

  test "import enqueues an import job" do
    assert_enqueued_with(job: ImportJob, args: ["munger"]) do
      chat "ghsa import munger", "nat"
    end

    assert_chatop_success
  end

  test "import ignores unknown sources" do
    assert_no_enqueued_jobs do
      chat "ghsa import bogus", "nat"
    end

    assert_chatop_failure
  end

  test "import respects locked sources" do
    ApplicationImporter.lock("munger")

    assert_no_enqueued_jobs do
      chat "ghsa import munger", "nat"
    end

    assert_chatop_failure
  end

  test "import cve enqueues an import job" do
    assert_enqueued_with(job: ImportJob, args: ["nvd", { cve_id: "CVE-2019-1234" }]) do
      chat "ghsa import cve CVE-2019-1234", "nat"
    end
  end

  test "import friends_of_php enqueues an import job" do
    assert_enqueued_with(job: ImportJob, args: ["friends_of_php", { specific_advisory_path: "symfony/form/CVE-2018-19789.yaml" }]) do
      chat "ghsa import friends_of_php symfony/form/CVE-2018-19789.yaml", "nat"
    end
  end

  test "import rubysec enqueues an import job" do
    assert_enqueued_with(job: ImportJob, args: ["rubysec", { specific_advisory_path: "gems/yard/CVE-2019-1020001.yml" }]) do
      chat "ghsa import rubysec gems/yard/CVE-2019-1020001.yml", "nat"
    end
  end

  test "import rustsec enqueues an import job" do
    assert_enqueued_with(job: ImportJob, args: ["rustsec", { specific_advisory_path: "crates/nanorand/RUSTSEC-2020-0089.md" }]) do
      chat "ghsa import rustsec crates/nanorand/RUSTSEC-2020-0089.md", "nat"
    end
  end

  # .ghsa lock tests

  test "lock locks the given source" do
    ApplicationImporter.unlock("munger")

    assert_changes(
      -> { ApplicationImporter.locked?("munger") },
      from: false,
      to: true,
    ) do
      chat "ghsa lock munger", "nat"
    end

    assert_chatop_success
  end

  test "lock ignores unknown sources" do
    assert_no_enqueued_jobs do
      chat "ghsa lock bogus", "nat"
    end

    assert_chatop_failure
  end

  test "lock noops for a source that's already locked" do
    ApplicationImporter.lock("munger")

    assert_no_changes(
      -> { ApplicationImporter.locked?("munger") },
    ) do
      chat "ghsa lock munger", "nat"
    end

    assert_chatop_success
  end

  # .ghsa unlock tests

  test "unlock unlocks the given source" do
    ApplicationImporter.lock("munger")

    assert_changes(
      -> { ApplicationImporter.locked?("munger") },
      from: true,
      to: false,
    ) do
      chat "ghsa unlock munger", "nat"
    end

    assert_chatop_success
  end

  test "unlock ignores unknown sources" do
    assert_no_enqueued_jobs do
      chat "ghsa unlock bogus", "nat"
    end

    assert_chatop_failure
  end

  test "unlock noops for a source that's already unlocked" do
    ApplicationImporter.unlock("munger")

    assert_no_changes(
      -> { ApplicationImporter.locked?("munger") },
    ) do
      chat "ghsa unlock munger", "nat"
    end

    assert_chatop_success
  end

  # .ghsa merge tests

  test "merges an open advisory review into another open advisory review" do
    advisory_review_a = create :advisory_review, feed_entry_type: :cve_feed_entry
    feed_entry_a = advisory_review_a.feed_entries.first
    assert_equal advisory_review_a.cve_id, feed_entry_a.cve_id

    feed_entry_b = create :repository_advisory_feed_entry, cve_id: feed_entry_a.cve_id
    advisory_review_b = create :advisory_review, feed_entry_count: 0
    advisory_review_b.feed_entries << feed_entry_b

    chat "ghsa merge #{advisory_review_a.ghsa_id} into #{advisory_review_b.ghsa_id}", "nat"
    assert_chatop_success

    advisory_review_a.reload
    advisory_review_b.reload

    assert_empty advisory_review_a.feed_entries
    assert_equal 2, advisory_review_b.feed_entries.length

    assert_nil advisory_review_a.cve_id
    assert_equal advisory_review_b.cve_id, feed_entry_a.cve_id
  end

  test "fails with reasonable failure message if an exception is raised during the merge" do
    advisory_review = create :advisory_review
    non_existent_ghsa_id = generate :ghsa_id
    chat "ghsa merge #{non_existent_ghsa_id} into #{advisory_review.ghsa_id}", "nat"
    assert_chatop_failure
    assert_equal ":warning: Failed to merge advisory reviews: Couldn't find AdvisoryReview with [WHERE `advisory_reviews`.`ghsa_id` = ?]", chatop_error
  end

  # .ghsa hydro publish tests

  test "hydro publish enqueues a publish job" do
    advisory = create :advisory
    PublishAdvisoryToHydroJob
      .expects(:perform_now)
      .with(advisory)
      .returns(mock("result", success?: true))

    chat "ghsa hydro publish #{advisory.ghsa_id}", "test_user"
  end

  test "hydro publish handles failure" do
    advisory = create :advisory
    PublishAdvisoryToHydroJob
      .expects(:perform_now)
      .with(advisory)
      .returns(mock("result", success?: false))

    chat "ghsa hydro publish #{advisory.ghsa_id}", "test_user"

    assert_chatop_failure
    assert_equal ":warning: Failed to publish the advisory.", chatop_error
  end

  test "hydro publish handles exceptions" do
    advisory = create(:advisory)
    exception = StandardError.new("Something went wrong")

    PublishAdvisoryToHydroJob
      .expects(:perform_now)
      .with(advisory)
      .raises(exception)

    chat "ghsa hydro publish #{advisory.ghsa_id}", "test_user"

    assert_chatop_failure
    assert_equal ":warning: An error occurred while publishing the advisory: Something went wrong", chatop_error
  end

  test "hydro publish handles nil advisory" do
    ghsa_id = "GHSA-a27d-j6j2-51w3"

    Advisory.expects(:find_by).with(ghsa_id: ghsa_id).returns(nil)

    chat("ghsa hydro publish #{ghsa_id}", "test_user")

    assert_chatop_failure
    assert_equal ":warning: Advisory not found.", chatop_error
  end
end
