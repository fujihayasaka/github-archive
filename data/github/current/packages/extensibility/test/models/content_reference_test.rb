# typed: true
# frozen_string_literal: true

require "test_helper"

class ContentReferenceTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user, login: "steves")
    @repo = create(:repository, owner: @user, from_example: :pull_request_source)

    @test_url = "https://github-integration.atlassian.net/test"
    @issue_comment = create(:issue_comment, user: @user, body: "test comment")

    other_user = create(:user, login: "acme")
    fork = create(:fork_repository, forker: other_user, fork_repo: @repo, from_example: :pull_request_fork)

    pull_request = create(:pull_request,
      issue: create(:issue, repository: @repo),
      base_repository: @repo,
      base_user: @user,
      base_ref: "master",
      head_repository: fork,
      head_user: other_user,
      head_ref: "topic",
    )

    @pr_review_comment = create(:pull_request_review_comment, pull_request: pull_request, user: @user)
    @integration = create(:integration)
  end

  context "scope#by_repo_and_id" do
    test "finds a reference based on the repo and id" do
      ref = ContentReference.create!(reference: @test_url, content: @issue_comment)
      assert_equal ref, ContentReference.by_repo_and_id(@issue_comment.repository, ref.id)
    end

    test "returns nil if repo is nil" do
      ref = ContentReference.create!(reference: @test_url, content: @issue_comment)
      assert_nil ContentReference.by_repo_and_id(nil, ref.id)
    end

    test "returns nil if repo doesnt match" do
      ref = ContentReference.create!(reference: @test_url, content: @issue_comment)
      assert_nil ContentReference.by_repo_and_id(create(:repository), ref.id)
    end

    test "returns nil if no reference is found" do
      assert_nil ContentReference.by_repo_and_id(@issue_comment.repository, 5)
    end
  end

  context "scope#by_content_and_reference" do
    test "finds a reference based on the content and reference" do
      first_reference = ContentReference.create!(reference: @test_url, content: @issue_comment)
      ContentReference.create!(reference: "#{@test_url}/new", content: @issue_comment)

      assert_equal first_reference, ContentReference.by_content_and_reference(@issue_comment, @test_url)
    end

    test "returns nil if no reference is found" do
      ContentReference.create!(reference: @test_url, content: @issue_comment)
      assert_nil ContentReference.by_content_and_reference(@issue_comment, "#{@test_url}/new")
    end
  end

  context "scope#all_by_content_and_references" do
    test "finds all references based on the content and reference" do
      first_reference = ContentReference.create!(reference: @test_url, content: @issue_comment)
      second_reference = ContentReference.create!(reference: "#{@test_url}/new", content: @issue_comment)

      assert_equal [first_reference, second_reference], ContentReference.all_by_content_and_references(@issue_comment, [@test_url, "#{@test_url}/new"]).sort
    end
  end

  context "#has_processed_attachment?" do
    test "returns false if no attachments" do
      reference = ContentReference.create!(reference: @test_url, content: @issue_comment)
      refute_predicate reference, :has_processed_attachment?
    end

    test "returns false if attachments aren't processed" do
      reference = ContentReference.create!(reference: @test_url, content: @issue_comment)
      create(:content_reference_attachment, content_reference: reference, state: :pending)
      refute_predicate reference, :has_processed_attachment?
    end

    test "returns true if attachment is processed" do
      reference = ContentReference.create!(reference: @test_url, content: @issue_comment)
      create(:content_reference_attachment, content_reference: reference, state: :processed)
      assert_predicate reference, :has_processed_attachment?
    end
  end

  context "#processed_attachment" do
    test "returns nil if no attachments" do
      reference = ContentReference.create!(reference: @test_url, content: @issue_comment)
      assert_nil reference.processed_attachment
    end

    test "returns nil if attachments aren't processed" do
      reference = ContentReference.create!(reference: @test_url, content: @issue_comment)
      create(:content_reference_attachment, content_reference: reference, state: :pending)
      assert_nil reference.processed_attachment
    end

    test "returns attachment if processed" do
      reference = ContentReference.create!(reference: @test_url, content: @issue_comment)
      attachment = create(:content_reference_attachment, content_reference: reference, state: :processed)
      assert_equal attachment, reference.processed_attachment
    end
  end

  test "before_create sets reference_hash" do
    reference = ContentReference.create(reference: @test_url, content: @issue_comment)
    assert_equal reference.reference_hash, Digest::SHA256.hexdigest(@test_url)
  end

  test "prevent_updates_of_reference prevents updates to reference" do
    new_url = "#{@test_url}/new"
    reference = ContentReference.create(reference: @test_url, content: @issue_comment)

    refute reference.update_attribute(:reference, new_url)
    reference.reload
    assert_equal @test_url, reference.reference
    assert_equal Digest::SHA256.hexdigest(@test_url), reference.reference_hash
  end

  test "prevent_updates_of_reference prevents updates to reference_hash" do
    new_url = "#{@test_url}/new"
    reference = ContentReference.create(reference: @test_url, content: @issue_comment)

    refute reference.update_attribute(:reference_hash, Digest::SHA256.hexdigest(new_url))
    reference.reload
    assert_equal @test_url, reference.reference
    assert_equal Digest::SHA256.hexdigest(@test_url), reference.reference_hash
  end

  test "content should be a supported type" do
    reference = ContentReference.create(reference: @test_url)
    reference.content = @user
    refute reference.save
    refute_predicate reference, :valid?
    assert_equal reference.errors.full_messages[0], "Content User is not a supported content type"

    reference.content = @issue_comment
    assert reference.save
    assert_predicate reference, :valid?

    reference.content = @pr_review_comment
    assert reference.save
    assert_predicate reference, :valid?
  end

  context "#matching_content_reference?" do
    test "regular users never match" do
      reference = create(:content_reference, reference: "https://www.example.com", content: @issue_comment)
      assert_equal false, reference.matching_content_reference?(@user)
    end
  end
end
