# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryIssueDependencyTest < GitHub::TestCase
  include ResiliencyHelpers

  fixtures do
    @defunkt  = create(:user, login: "defunkt",  plan: "medium")
    @simple   = create(:repository, name: "simple",   owner: @defunkt)
    @org = create(:organization)
    @org_repo = create(:repository, name: "simple", owner: @org)
  end

  context "#populate_labels" do
    test "when owned by organization with labels, queues job to create labels owner's user_labels" do
      owner = create(:organization)
      create_list(:user_label, 10, user: owner)
      repo = create(:repository, owner: owner)
      repo = Repositories::Public.find_active!(repo.id)

      expected_labels = owner.user_labels
      refute_empty expected_labels # sanity check
      only = [RepositoryPopulateLabelsJob]
      perform_enqueued_jobs(only: only) { repo.populate_labels }

      expected_labels.each do |user_label|
        label = repo.labels.where(name: user_label.name).first
        refute_nil label, "should have created label '#{user_label.name}'"
        assert_equal user_label.color, T.must(label).color
        assert_equal user_label.description, T.must(label).description
      end

      # sanity check: org-specific labels will differ from the Label default list
      refute_same_elements repo.labels.pluck(:name), Label::DEFAULT_LABEL_NAMES.to_a
    end

    test "when org has no labels, creates no repo labels" do
      owner = create(:organization)
      owner.user_labels.destroy_all

      repo = create(:repository, owner: owner)
      repo = Repositories::Public.find_active!(repo.id)

      only = [RepositoryPopulateLabelsJob]
      perform_enqueued_jobs(only: only) { repo.populate_labels }
      assert_empty repo.labels
    end

    test "when owned by a user creates labels with default labels' name, color, and description" do
      expected_labels = Label.initial_labels
      repo = create(:repository)
      repo = Repositories::Public.find_active!(repo.id)


      only = [RepositoryPopulateLabelsJob]
      perform_enqueued_jobs(only: only) { repo.populate_labels }

      expected_labels.each do |hash|
        label = repo.labels.where(name: hash[:name]).first
        refute_nil label, "should have created label '#{hash[:name]}'"
        assert_equal hash[:color], T.must(label).color
        assert_equal hash[:description], T.must(label).description
      end

      assert_same_elements repo.labels.pluck(:name), Label::DEFAULT_LABEL_NAMES.to_a
    end
  end

  test "sorted_labels returns labels sorted by name" do
    label_names = %w(carrot broccoli asparagus)
    label_names.each do |name|
      @simple.labels.create(name: name)
    end

    assert_equal label_names.reverse, @simple.sorted_labels.map(&:name)
  end

  test "sorted_labels puts labels assigned to a given issue first" do
    labels = %w(carrot broccoli asparagus).map do |name|
      @simple.labels.create(name: name)
    end

    issue = create(:issue, repository: @simple)
    issue.add_labels([labels[1]])

    assert_equal %w(broccoli asparagus carrot), @simple.sorted_labels(issue_or_pr: issue).map(&:name)
  end

  test "sorted_labels puts labels assigned to a given pull request first" do
    labels = %w(carrot broccoli asparagus).map do |name|
      @simple.labels.create(name: name)
    end

    pull = create(:pull_request, :disable_disk_access, repository: @simple, user: @defunkt)
    pull.issue.add_labels([labels[1]])

    assert_equal %w(broccoli asparagus carrot), @simple.sorted_labels(issue_or_pr: pull).map(&:name)
  end

  test "sorted_labels warms the label html cache on request" do
    labels = ["carrot :carrot:", "broccoli :broccoli:", "apple :apple:"].map do |name|
      @simple.labels.create(name: name)
    end

    # Make sure that we actually need to cache the HTML for at least one of label under test.
    refute EmojiHtmlStringRenderer::SAFE_STRING_REGEXP.match?(labels.first.name)

    result = @simple.sorted_labels(cache_label_html: true)

    # From this point forward we shouldn't even read from the cache when
    # accessing `name_html` on a label.
    GitHub.cache.stubs(:get) # stub cache get to handle unrelated calls (e.g. feature flags, etc)
    GitHub.cache.stubs(:get).with(regexp_matches(/label:/)).raises(
      StandardError.new("should not have called GitHub.cache.get")
    ) do
      GitHub.cache.stubs(:get_multi).raises(
        StandardError.new("should not have called GitHub.cache.get_multi")
      ) do
        # Call the method that would access the cache if the `cache_label_html`
        # flag were not working.
        assert result.map(&:name_html).all?
      end
    end
  end

  context "#find_labels" do
    test "finds a label when it exists in that repository" do
      repo = create(:repository)
      label = create(:label, name: "bug", repository: repo)

      assert_equal label, repo.find_labels(label.id).first
    end

    test "does not find a label when it exists in a different repository" do
      label = create(:label)
      repo = create(:repository)

      assert_empty repo.find_labels(label.id)
    end

    test "doesn't find a label if it doesn't exist" do
      repo = create(:repository)

      refute repo.find_labels(1).any?
    end
  end

  context "#help_wanted_label" do
    test "finds label whose name starts with 'help wanted', case insensitive" do
      label = create(:label, name: "Help Wanted Please")
      assert_equal label, label.repository.help_wanted_label
    end

    test "prefers exact match" do
      repo = create(:repository)
      create(:label, name: "Help Wanted Please", repository: repo)
      label2 = create(:label, name: "Help Wanted", repository: repo)
      create(:label, name: "help wanted for the people", repository: repo)

      assert_equal label2, repo.help_wanted_label
    end
  end

  context "#good_first_issue_label" do
    test "finds label whose name starts with 'good first issue', case insensitive" do
      label = create(:label, name: "GOOD first issue for new folks")
      assert_equal label, label.repository.good_first_issue_label
    end

    test "prefers exact match" do
      repo = create(:repository)
      create(:label, name: "Good FIRST issue HERE", repository: repo)
      label2 = create(:label, name: "Good FIRST issue", repository: repo)
      create(:label, name: "Good first IsSuE for all y'all", repository: repo)

      assert_equal label2, repo.good_first_issue_label
    end
  end

  test "creates repo with initial labels" do
    repo = T.let(nil, T.nilable(Repository))
    perform_enqueued_jobs(only: RepositoryPopulateLabelsJob) do
      repo = create(:repository, :full_creation, name: "coffee-script", owner: @defunkt)
    end
    labels = T.must(repo).labels.map(&:name)
    assert labels.include?("bug")
    assert labels.include?("enhancement")
  end

  context "#memex_suggestion_hash" do
    test "returns a repo in the shape memex_suggestion require" do
      repo = @simple
      expected = {
        id: repo.id,
        isForked: repo.fork?,
        isPublic: repo.public?,
        isArchived: repo.archived?,
        hasIssues: repo.has_issues?,
        name: repo.name,
        nameWithOwner: repo.nwo,
        url: repo.permalink,
        pushedAt: repo.pushed_at&.utc&.iso8601,
      }
      assert_equal repo.memex_suggestion_hash, expected
    end
  end

  context "#memex_column_hash" do
    test "retuns a repo in the shape memex_columns require" do
      repo = @simple
      result = repo.memex_column_hash
      expected = {
        id: repo.id,
        isForked: repo.fork?,
        isPublic: repo.public?,
        isArchived: repo.archived?,
        hasIssues: repo.has_issues?,
        name: repo.name,
        nameWithOwner: repo.nwo,
        url: repo.permalink,
      }
      assert_equal result, expected
    end
  end

  context ".open_pull_request_count_for", skip_enterprise: true do
    test "returns the number of open pull requests for a given user" do
      owner = create(:user)
      repo = create(:repository, owner: owner)
      create(:pull_request, :disable_disk_access, repository: repo, user: owner)

      assert_equal 1, repo.open_pull_request_count_for(owner)
    end

    test "returns the number of open pull requests for a spammy user" do
      owner = create(:spammy_user)
      repo = create(:repository, owner: owner, user_hidden: 1)
      create(:pull_request, :disable_disk_access, repository: repo, user: owner)
      viewer = create(:user)

      assert_equal 1, repo.open_pull_request_count_for(owner)
      assert_equal 0, repo.open_pull_request_count_for(viewer)
    end
  end

  context ".open_issue_count_for", skip_enterprise: true do
    test "returns the number of open issues for a given user" do
      owner = create(:user)
      repo = create(:repository, owner: owner)
      create(:issue, repository: repo)

      assert_equal 1, repo.open_issue_count_for(owner)
    end

    test "returns the number of open issues for a spammy user" do
      owner = create(:spammy_user)
      repo = create(:repository, owner: owner, user_hidden: 1)
      create(:issue, repository: repo)
      viewer = create(:user)

      assert_equal 1, repo.open_issue_count_for(owner)
      assert_equal 0, repo.open_issue_count_for(viewer)
    end
  end

  context "issue_forms_type_field_enabled?" do
    test "returns true if repo owner is an organization, `issue_types` FF is enabled for org and viewer is a member of the org" do
      viewer = create(:user)
      @org.add_member(viewer)
      GitHub.flipper[:issue_types].enable(@org)

      assert @org_repo.issue_forms_type_field_enabled?(viewer)
    end

    test "returns true if repo owner is an organization, `issue_types` FF is enabled for org and viewer is logged in" do
      GitHub.flipper[:issue_types].enable(@org)

      assert @org_repo.issue_forms_type_field_enabled?(create(:user))
    end

    test "returns false if viewer is anonymous" do
      GitHub.flipper[:issue_types].enable(@org)

      refute @org_repo.issue_forms_type_field_enabled?(nil)
    end

    test "returns false if FF is disabled for org" do
      viewer = create(:user)
      @org.add_member(viewer)
      GitHub.flipper[:issue_types].disable(@org)

      refute @org_repo.issue_forms_type_field_enabled?(viewer)
    end
  end

  context "open_issue_and_pr_counts" do
    test "returns nil if database fails and return_nil_on_failure is set to true" do
      repo = create :repository, owner: @org, from_example: :pull_request_source

      create :issue, repository: repo
      create :pull_request, :with_mergeable_head, repository: repo

      db_result = prevent_connections_to(ApplicationRecord::IssuesPullRequests) do
        Repository.open_issue_and_pr_counts(repository_ids: [repo.id], return_nil_on_failure: true)
      end

      assert_nil db_result
    end
  end
end
