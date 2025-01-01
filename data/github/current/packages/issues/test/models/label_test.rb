# typed: true
# frozen_string_literal: true

require "test_helper"

class LabelTest < GitHub::TestCase
  include HydroTestHelpers
  include StringFromBinaryTestHelper
  include BackgroundDeletesTestHelpers

  fixtures do
    setup_search
    @user    = create :user
    @repo    = create :repository, has_discussions: true
    @label   = create :label, repository: @repo, color: "ff0000", description: "some-description"
    @issue   = create :issue, repository: @repo, user: @repo.owner
    @labeled = create :issue, repository: @repo, user: @repo.owner
    @labeled.labels << @label
    @discussion = create :discussion, repository: @repo
    @labelled_discussion = create :discussion, repository: @repo
    @labelled_discussion.labels << @label
  end

  teardown_once do
    teardown_search
  end

  context "#issues_count" do
    test "counts open issues and pull requests with the label" do
      pr_issue = create(:issue, repository: @repo, labels: [@label])
      create(:pull_request, :disable_disk_access, repository: @repo, issue: pr_issue)

      assert_equal 2, @label.issues_count
    end
  end

  context "#issues_without_pull_requests_count" do
    test "counts only open issues with the label, not PRs" do
      pr_issue = create(:issue, repository: @repo, labels: [@label])
      create(:pull_request, :disable_disk_access, repository: @repo, issue: pr_issue)

      assert_equal 1, @label.issues_without_pull_requests_count
    end
  end

  test "sets lowercase_name from name on validation" do
    label = build(:label, name: "My Best Label")
    label.valid?
    assert_equal "my best label", label.lowercase_name
  end

  test "sets label_name from name on saving" do
    label = build(:label, name: "My Best Label💩")
    label.save
    assert_equal "My Best Label💩", label.reload.label_name
  end

  test "raises error if label_name is not unique" do
    # This test bypasses the rails validation and attempts to create
    # labels with the same name. This simulates a race condition when
    # 2 requests pass the rails validation at the same time and we rely
    # on the database unique constraint to fail the creation

    assert_raises ActiveRecord::RecordNotUnique do
      label1 = build(:label, name: "My Best Label💩", repository: @repo)
      label1.save(validate: false) # bypass rails validation
      assert_equal "My Best Label💩", label1.label_name
      label2 = build(:label, name: "My Best Label💩", repository: @repo)
      label2.save(validate: false) # bypass rails validation
    end
  end

  test "Updating the color of a label whose name is already too long doesn't fail" do
    label = build(:label, repository: @repo)
    label.save(validate: false)

    # Simulate `label_name` being nil and `name` longer than
    # that permissible by the `label_name` column
    long_name = rand(36**(257)).to_i.to_s(36)
    label.update_column(:name, long_name)
    label.update_column(:label_name, nil)

    label.update_attribute(:color, "667")
    refute_predicate label, :label_name_changed?
    assert_nil label.label_name
  end

  test "validating label with name containing emoji does not cause a change" do
    label = build(:label, name: "Oh hi #{GRIN_EMOJI}")
    label.save!
    label.reload
    assert_predicate label, :valid?
    refute_predicate label, :changed?
    refute_predicate label, :lowercase_name_changed?
  end

  test "lists label issues" do
    assert_equal [@labeled], @label.issues
  end

  test "lists label discussions" do
    assert_equal [@labelled_discussion], @label.discussions
  end

  test "lists issue labels" do
    assert_equal [@label], @labeled.labels
  end

  test "lists discussion labels" do
    assert_equal [@label], @labelled_discussion.labels
  end

  test "allows 4-byte unicode emoji in description field" do
    emoji = "Grin #{GRIN_EMOJI} Emoji"
    label = build(:label, description: emoji)

    assert_predicate label, :valid?
  end

  test "limits length of description field" do
    description = "a" * (Labelable::DESCRIPTION_MAX_LENGTH + 1)
    label = build(:label, description: description)

    refute_predicate label, :valid?
    assert_includes label.errors.messages[:description],
      "is too long (maximum is #{Labelable::DESCRIPTION_MAX_LENGTH} characters)"
  end

  test "limits length of name field" do
    name = "a" * (Labelable::NAME_MAX_LENGTH + 1)
    label = build(:label, name: name)

    refute_predicate label, :valid?
    assert_includes label.errors.messages[:name],
      "is too long (maximum is #{Labelable::NAME_MAX_LENGTH} characters)"
  end

  test "adds label to issue" do
    assert_equal [],         @issue.labels
    assert_equal [@labeled], @label.issues
    @issue.labels << @label
    assert_equal [@label],           @issue.labels.reload
    assert_equal [@issue, @labeled], @label.issues.reload.sort_by(&:id)
  end

  test "removes label from issue" do
    assert_equal [@label], @labeled.labels
    @labeled.labels.delete @label
    assert_equal [], @labeled.labels.reload
  end

  test "adds label to discussion" do
    assert_equal [], @discussion.labels
    assert_equal [@labelled_discussion], @label.discussions
    @discussion.labels << @label
    assert_equal [@label], @discussion.labels.reload
    assert_same_elements [@labelled_discussion, @discussion], @label.discussions.reload
  end

  test "removes label from discussion" do
    assert_equal [@label], @labelled_discussion.labels
    assert_equal [@labelled_discussion], @label.discussions
    @labelled_discussion.labels.delete @label
    assert_equal [], @labelled_discussion.labels.reload
    assert_equal [], @label.discussions.reload
  end

  test "must have a six digit alnum color" do
    @label.color = "blaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaah!"
    refute_predicate @label, :valid?

    @label.color = "color=aaaaaa'};([],[][(![]+[]"
    refute_predicate @label, :valid?

    @label.color = "666666\nfoo"
    refute_predicate @label, :valid?

    @label.color = "666666\n"
    refute_predicate @label, :valid?

    @label.color = "666666"
    assert_predicate @label, :valid?

    @label.color = "c0c0c0"
    assert_predicate @label, :valid?
  end

  test "requires a name" do
    label = build(:label, name: "")

    refute_predicate label, :valid?
    assert_predicate label.errors[:name], :present?
  end

  test "requires case-insensitive uniqueness" do
    create(:label, name: "bug", repository: @repo)
    label = build(:label, name: "Bug", repository: @repo)
    refute_predicate label, :valid?
    assert_predicate label.errors[:name], :present?
  end

  test "requires case-insensitive uniqueness, even with emoji" do
    create(:label, name: "bug #{GRIN_EMOJI}", repository: @repo)
    label = build(:label, name: "Bug #{GRIN_EMOJI}", repository: @repo)
    refute_predicate label, :valid?
    assert_predicate label.errors[:name], :present?
  end

  test "color shorthand is expanded on validation" do
    @label.color = "666"
    assert_predicate @label, :valid?
    assert_equal "666666", @label.color
  end

  test "strips trailing whitespace from name" do
    @label.name = "foo "
    assert_predicate @label, :valid?
    assert_equal "foo", @label.name
  end

  test "strips leading whitespace from name" do
    @label.name = " foo"
    assert_predicate @label, :valid?
    assert_equal "foo", @label.name
  end

  test "replaces newlines with spaces in name" do
    @label.name = "f\noo"
    assert_predicate @label, :valid?
    assert_equal "f oo", @label.name
  end

  test "strips trailing whitespace from description" do
    @label.description = "foo "

    assert_predicate @label, :valid?
    assert_equal "foo", @label.description
  end

  test "strips leading whitespace from description" do
    @label.description = " foo"

    assert_predicate @label, :valid?
    assert_equal "foo", @label.description
  end

  test "replaces newlines with spaces in description" do
    @label.description = "f\noo"

    assert_predicate @label, :valid?
    assert_equal "f oo", @label.description
  end

  test "doesn't accept non-hex 6-letter colors" do
    @label.color = "yellow"
    refute_predicate @label, :valid?
  end

  test "can't have commas" do
    @label.name = "blah,blah"
    refute_predicate @label, :valid?
  end

  test "can be alphanumericish" do
    @label.name = "ah-ha tékkub_likesPI 3.14"
    assert_predicate @label, :valid?
  end

  [:name, :lowercase_name].each do |field|
    test "supports emoji for #{field}" do
      encoded_value = "hey #{GRIN_EMOJI}"
      encoded_value2 = "hey \xF0\x9F\x98\x80"
      encoded_value3 = "hola 🙃"

      if field == :lowercase_name
        label = create(:label, name: encoded_value, lowercase_name: encoded_value)
        assert_multibyte_tracked_changes(label, field, encoded_value, encoded_value2, encoded_value3, :name)
      else
        label = create(:label, field => encoded_value)
        assert_multibyte_tracked_changes(label, field, encoded_value, encoded_value2)
      end

      assert_predicate label, :valid?
    end
  end

  test "supports StringFromBinary for description" do
    label = create(:label, description: "some-description")

    assert_valid label
    assert_equal Encoding::UTF_8, label.description.encoding
    assert_equal StringFromBinary.new, label.type_for_attribute(:description)
  end

  test "cannot include only native emoji" do
    @label.name = GRIN_EMOJI

    refute_predicate @label, :valid?
    assert_includes @label.errors[:name], "must contain more than native emoji"
  end

  test "can be twitterish" do
    @label.name = "@defunkt"
    assert_predicate @label, :valid?
  end

  test "can be pipish" do
    @label.name = "|-| |"
    assert_predicate @label, :valid?
  end

  test "can be hashtaggish" do
    @label.name = "#realtalk"
    assert_predicate @label, :valid?
  end

  context "#default_for" do
    test "finds a label provided the name of a default" do
      result = Label.default_for("help wanted")
      assert_instance_of Label, result
      refute_predicate result, :persisted?
    end

    test "doesn't find a label provided a name that isn't a default" do
      assert_nil Label.default_for("cheese")
    end
  end

  test "can sort labels intelligently grouped by issue count" do
    versions_with_issues = %w(@user 1.0.9 deploy 2.0 zebra)
    sorted_versions_with_issues = %w(1.0.9 2.0 deploy @user zebra)
    versions_without_issues = %w(@tmm1 10.0 bug 2.0.3)
    sorted_versions_without_issues = %w(2.0.3 10.0 bug @tmm1)
    with_issues = []
    without_issues = []

    versions_with_issues.each do |version|
      label = create :label, repository: @repo, name: version, color: "ff0000"
      label.issues << create(:issue, repository: @repo, user: @repo.owner)
      with_issues << label
    end

    versions_without_issues.each do |version|
      without_issues << create(:label, repository: @repo, name: version, color: "ff0000")
    end

    perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
      @repo.issues.each(&:synchronize_search_index)
    end

    Elastomer::Indexes::Issues.new.refresh

    labels = without_issues + with_issues

    # by default we group sort labels with/without issues
    sorted_labels = Label.smart_sort(labels, true)

    # label group with issues
    sorted_labels[0...sorted_versions_with_issues.size].each_with_index do |label, idx|
      assert_equal sorted_versions_with_issues[idx], label.name
      assert label.issues.count > 0
    end

    # label group without issues
    sorted_labels[sorted_versions_with_issues.size..-1].each_with_index do |label, idx|
      assert_equal sorted_versions_without_issues[idx], label.name
      assert label.issues.count == 0
    end
  end

  test "can sort labels intelligently" do
    versions = %w(PRIORITY issues Engineering 1.1.0 i18n 1.12.3 9.54 codeload)
    sorted_versions = %w(1.1.0 1.12.3 9.54 codeload Engineering i18n issues PRIORITY)
    labels = []

    versions.each do |version|
      labels << create(:label, name: version, color: "ff0000")
    end

    sorted_labels = Label.smart_sort(labels)

    sorted_labels.each_with_index do |label, idx|
      assert_equal sorted_versions[idx], label.name
    end
  end

  test "can contain unicode characters above 0xffff" do
    @label.name = "怎"
    assert_predicate @label, :valid?

    bell_emoji = [0x1F514].pack("U")
    @label.name = "#{bell_emoji} label"
    assert_predicate @label, :valid?
  end

  test "fails adding duplicate labels" do
    assert_raises ActiveRecord::RecordNotUnique do
      @labeled.labels << @label
    end
  end

  test "fails adding duplicate labels to a discussion" do
    assert_raises ActiveRecord::RecordNotUnique do
      @labelled_discussion.labels << @label
    end
  end

  test "handles search slugs" do
    label = Label.new(name: "bug")
    assert_equal "bug", label.to_search_slug

    label.name = "real gnarly bug"
    assert_equal '"real gnarly bug"', label.to_search_slug
  end

  test "async_path_uri encodes correctly" do
    @label.name = "c'était/ici"
    assert @label.async_path_uri.sync.to_s.end_with?("c%27%C3%A9tait%2Fici")
  end

  test "triggers Issue#update_repo_community_profile after commit", skip_enterprise: true do
    repo = create(:repository, community_profile: create(:community_profile))
    label = create(:label, name: "bug", repository: repo)
    issue = create(:issue, repository: repo, labels: [label])

    CommunityProfileUpdateHelpWantedCountersJob.expects(:enqueue_once_per_interval).twice.
      with(args: [repo.id], interval: CommunityProfile::UPDATE_INTERVAL)

    label.update_attribute(:name, "help wanted")
    label.update_attribute(:name, "good first issue")
  end

  test "triggers Issue#update_repo_community_profile even for variant of label", skip_enterprise: true do
    CommunityProfile.any_instance.stubs(:set_baseline_health_metrics)

    repo = create(:repository, community_profile: create(:community_profile))
    label = create(:label, name: "bug", repository: repo)
    issue = create(:issue, repository: repo, labels: [label])

    CommunityProfileUpdateHelpWantedCountersJob.expects(:enqueue_once_per_interval).twice.
      with(args: [repo.id], interval: CommunityProfile::UPDATE_INTERVAL)

    label.update_attribute(:name, "Help Wanted Right Now")
    label.update_attribute(:name, "Good First Issue for Beginners")
  end

  context "#default?" do
    test "returns true for a default label" do
      issue = create(:issue)
      issue.labels.each { |label| assert_predicate label, :default? }
    end

    test "returns false for a non default label" do
      label = create :label, name: "customer-feedback"
      refute_predicate label, :default?
    end
  end

  context ".destroy" do
    test "destroys the dependent issues_label" do
      issue_id = @labeled.id

      assert_equal 1, IssuesLabels.where(issue_id: issue_id).count
      perform_enqueued_jobs only: [DestroyIssuesLabelsJob, DestroyDependentRecordsJob] do
        @label.destroy
      end

      assert_equal 0, IssuesLabels.where(issue_id: issue_id).count
    end

    context "with a modifying user" do
      test "it touches an open issue" do
        GitHub.context.push(actor: @user)
        timestamp = @labeled.updated_at

        Timecop.freeze(3.hours.from_now) do
          perform_enqueued_jobs only: [DestroyIssuesLabelsJob, CreateUnlabeledEventJob] do
            @label.destroy
          end
          refute_equal @labeled.reload.updated_at, timestamp
        end
      end

      test "generates an event on open issue" do
        GitHub.context.push(actor: @user)
        assert_difference "@labeled.events.count", 1 do
          perform_enqueued_jobs only: [DestroyIssuesLabelsJob, CreateUnlabeledEventJob] do
            @label.destroy
          end
        end
        event = @labeled.events.last
        assert_equal "unlabeled", event.event
      end

      test "records the user who deleted" do
        GitHub.context.push(actor: @user)
        perform_enqueued_jobs only: [DestroyIssuesLabelsJob, CreateUnlabeledEventJob] do
          @label.destroy
        end
        event = @labeled.events.last
        assert_equal @user, event.actor
      end

      test "deletes it" do
        GitHub.context.push(actor: @user)
        @label.destroy
        assert @label.destroyed?
      end

      test "does not generate event on closed issues" do
        GitHub.context.push(actor: @user)
        @labeled.close!

        assert_no_difference "@labeled.events.count" do
          @label.destroy
        end
      end

      test "does not touch event on closed issues" do
        GitHub.context.push(actor: @user)
        @labeled.close!
        @labeled.reload
        timestamp = @labeled.updated_at

        Timecop.freeze(3.hours.from_now) do
          @label.destroy
        end

        assert_equal @labeled.updated_at, timestamp
      end
    end
  end

  context ".find_by_name" do
    test "returns label with the given name, ignoring case" do
      label = create(:label, name: "Practical Rejected Glove")
      assert_equal label, Label.find_by_name("practical rejected glove")
    end
  end

  context "with_name scope" do
    test "searches labels with emoji" do
      name = "ready-for-review \u{1f440}"
      label = create(:label, name: name)

      assert_equal [label], Label.with_name(name)
      assert_equal [label], Label.with_name([name, "other label #{GRIN_EMOJI}"])
    end

    test "includes label whose name matches, ignoring case" do
      label = create(:label, name: "Scientific Flawless Feline")
      create(:label, name: "Scientific Flawless Fowl")

      results = Label.with_name("scientific FLAWLESS felINE")

      assert_equal [label], results
    end

    test "includes labels with any of the given names, ignoring case" do
      label1 = create(:label, name: "greater Dallas area")
      label2 = create(:label, name: "Houston team")

      results = Label.with_name(["greater dallas area", "houston team"])

      assert_same_elements [label1, label2], results
    end
  end

  context "with no modifying user" do
    test "deletes it" do
      GitHub.context.push(actor: @user)
      @label.destroy
      assert @label.destroyed?
    end

    test "does not generate event on closed issues" do
      GitHub.context.push(actor: @user)
      @labeled.close!

      assert_no_difference "@labeled.events.count" do
        perform_enqueued_jobs only: [DestroyIssuesLabelsJob, CreateUnlabeledEventJob] do
          @label.destroy
        end
      end
    end

    test "does not touch event on closed issues" do
      GitHub.context.push(actor: @user)
      @labeled.close!
      @labeled.reload
      timestamp = @labeled.updated_at

      Timecop.freeze(3.hours.from_now) do
        perform_enqueued_jobs only: [DestroyIssuesLabelsJob, CreateUnlabeledEventJob] do
          @label.destroy
        end
      end

      assert_equal @labeled.updated_at, timestamp
    end

    test "reindexes affected issues" do
      GitHub.context.push(actor: @user)

      Search.expects(:add_to_search_index).with("issue", @labeled.id).once

      assert_enqueued_with job: RemoveFromSearchIndexJob, args: ["label", @label.id, @label.repository_id] do
        assert_enqueued_with job: DeliverHookEventJob do
          perform_enqueued_jobs only: [DestroyIssuesLabelsJob, CreateUnlabeledEventJob, IssueOrchestration.job_class] do
            assert_enqueued_with job: ProcessEventJob, args: ["IssuesEvent", [:unlabeled, @labeled.id, @user.id, { label_id: @label.id }]] do
              @label.destroy
            end
          end
        end
      end
    end

    test "reindexes pull request for affected issues" do
      GitHub.context.push(actor: @user)
      example_repo :encodings, @repo

      @pull = create(:pull_request,
        repository: @repo,
        base_ref: "empty-branch",
        head_ref: "master",
        issue: @labeled,
      )

      Search.expects(:add_to_search_index).with("pull_request", @pull.id).once

      assert_enqueued_with job: RemoveFromSearchIndexJob, args: ["label", @label.id, @repo.id] do
        assert_enqueued_with job: DeliverHookEventJob do
          perform_enqueued_jobs only: [DestroyIssuesLabelsJob, CreateUnlabeledEventJob, IssueOrchestration.job_class] do
            assert_enqueued_with job: ProcessEventJob,
              args: ["PullRequestEvent", [:unlabeled, @pull.id, @user.id, { label_id: @label.id }]] do
              @label.destroy
            end
          end
        end
      end
    end
  end

  context "with_name_like scope" do
    test "finds labels whose name includes an emoji" do
      label1 = create(:label, name: "\u{1f440} look")
      label2 = create(:label, name: "\u{1f440} eyes")
      label3 = create(:label, name: "#{GRIN_EMOJI} smile")

      results = Label.with_name_like("\u{1f440}")

      assert_includes results, label1
      assert_includes results, label2
      refute_includes results, label3
    end

    test "includes labels whose name begins with given string, case insensitive" do
      label1 = create(:label, name: "Overwatch - Mercy")
      label2 = create(:label, name: "Overwatch - Moira")
      label3 = create(:label, name: "Dragon Age - Alistair")

      results = Label.with_name_like("overwatch")

      assert_includes results, label1
      assert_includes results, label2
      refute_includes results, label3
    end
  end

  context ".help_wanted" do
    test "returns 'help wanted' label" do
      label = create(:label, name: "Help Wanted", repository: @repo)
      assert_equal label, @repo.labels.help_wanted
    end
  end

  context ".similar_to_help_wanted" do
    test "returns label starting with 'help wanted'" do
      label = create(:label, name: "Help Wanted Please", repository: @repo)
      assert_equal label, @repo.labels.similar_to_help_wanted
    end
  end

  context ".good_first_issue" do
    test "returns 'good first issue' label" do
      label = create(:label, name: "Good First Issue", repository: @repo)
      assert_equal label, @repo.labels.good_first_issue
    end
  end

  context ".similar_to_good_first_issue" do
    test "returns label starting with 'good first issue'" do
      label = create(:label, name: "Good First Issue for New Folks", repository: @repo)
      assert_equal label, @repo.labels.similar_to_good_first_issue
    end
  end

  context "#update_issues callback" do
    test "unicode label name added to issue doesn't trigger callback" do
      label = create(:label, name: "Oh hi #{GRIN_EMOJI}", repository: @repo)
      label.reload

      Label.any_instance.expects(:update_issues).never
      issue = create(:issue, repository: @repo, labels: [label])
    end

    test "non-unicode label added to issue doesn't trigger callback" do
      label = create(:label, name: "Oh hi", repository: @repo)
      label.reload

      Label.any_instance.expects(:update_issues).never
      issue = create(:issue, repository: @repo, labels: [label])
    end

    test "change to label name triggers search indexing on issue" do
      label = create(:label, name: "Oh hi", repository: @repo)
      label.reload

      issue = create(:issue, repository: @repo, labels: [label])

      Issue.any_instance.expects(:synchronize_search_index).once

      perform_enqueued_jobs only: Issues::ReindexIssuesForAssociationJob do
        label.update!(name: "Oh bye")
      end
    end

    test "search indexing on issue is not triggered if label name not updated" do
      label = create(:label, name: "Oh hi", repository: @repo)
      label.reload

      issue = create(:issue, repository: @repo, labels: [label])

      Issue.any_instance.expects(:synchronize_search_index).never

      label.update!(description: "Hi there")
    end
  end

  context "#update_discussions callback" do
    test "does nothing if the name has not changed" do
      Discussion.any_instance.expects(:synchronize_search_index).never
      @label.update!(description: "changed description")
    end

    test "reindexes labelled discussions when the name has changed" do
      Discussion.any_instance.expects(:synchronize_search_index).once
      @label.update!(name: "#{@label.name}-changed")
    end
  end

  context "#url" do
    test "returns a valid label URL" do
      user = create(:user, login: "testing")
      repo = create(:repository, name: "the", owner: user)
      label = create(:label, name: "url-generation-code", repository: repo)

      assert_equal "https://github.com/testing/the/labels/url-generation-code", label.url
    end

    test "returns nil for label without repository" do
      label = Label.create!(repository_id: 99999, name: "url-generation-code", created_at: Time.now)
      assert_nil label.url
    end

    test "is in sync with #async_path_uri" do
      assert_equal @label.async_path_uri.sync.to_s, @label.url.gsub(GitHub.url, "")
    end
  end

  context "#memex_column_hash" do
    test "returns hash representation of the label" do
      label = create(:label, color: "ffffff", name: "bug :bug:")

      assert_equal(
        {
          color: "ffffff",
          id: label.id,
          name: "bug :bug:",
          nameHtml: "bug 🐛",
          url: label.url,
        },
        label.memex_column_hash
      )
    end
  end

  context "#memex_suggestion_hash" do
    test "returns hash representation of the label with selection flag" do
      label = create(:label, color: "ffffff", name: "bug :bug:")

      assert_equal(
        {
          color: "ffffff",
          id: label.id,
          name: "bug :bug:",
          nameHtml: "bug 🐛",
          selected: true,
          url: label.url
        },
        label.memex_suggestion_hash(selected: true)
      )
    end
  end

  context "#csv_column_value" do
    test "returns the name of the label" do
      label = create(:label, name: "bug :bug:")

      assert_equal "bug :bug:", label.csv_column_value
    end
  end

  unless GitHub.enterprise?
    context "instrumentation to hydro" do
      test "label.update" do
        label = create(:label)
        label.update! description: "gummi bears"

        message = {
          label: Hydro::EntitySerializer.label(label),
          actor: Hydro::EntitySerializer.user(@owner),
        }

        assert_hydro_published(message, schema: "github.v1.LabelUpdate")
      end

      test "label.delete" do
        label = create(:label)
        label.destroy!

        message = {
          label: Hydro::EntitySerializer.label(label),
          actor: Hydro::EntitySerializer.user(@owner),
        }

        assert_hydro_published(message, schema: "github.v1.LabelDelete")
      end
    end
  end

  context "instrument label.update event" do
    test "updating only the name of a payload" do
      events = subscribe "label.update"

      old_name = @label.name
      actor_id = GitHub.context[:actor_id] || User.ghost.id
      @label.update!(name: "new-name")

      assert event = events.pop, "a label.update event was expected"
      assert_equal @label.id, event.payload[:label_id]
      assert_equal actor_id, event.payload[:actor_id]
      assert_equal old_name, event.payload[:changes][:old_name]
      assert_nil event.payload[:changes][:old_color]
      assert_nil event.payload[:changes][:old_description]
    end

    test "updating only the description of a payload" do
      events = subscribe "label.update"

      old_desc = @label.description
      actor_id = GitHub.context[:actor_id] || User.ghost.id
      @label.update!(description: "new-desc")

      assert event = events.pop, "a label.update event was expected"
      assert_equal @label.id, event.payload[:label_id]
      assert_equal actor_id, event.payload[:actor_id]
      assert_equal old_desc, event.payload[:changes][:old_description]
      assert_nil event.payload[:changes][:old_color]
      assert_nil event.payload[:changes][:old_name]
    end

    test "updating only the color of a payload" do
      events = subscribe "label.update"

      old_color = @label.color
      actor_id = GitHub.context[:actor_id] || User.ghost.id
      @label.update!(color: "ffffff")

      assert event = events.pop, "a label.update event was expected"
      assert_equal @label.id, event.payload[:label_id]
      assert_equal actor_id, event.payload[:actor_id]
      assert_equal old_color, event.payload[:changes][:old_color]
      assert_nil event.payload[:changes][:old_name]
      assert_nil event.payload[:changes][:old_description]
    end

    test "updating multiple fields for a label" do
      events = subscribe "label.update"

      old_color = @label.color
      old_name = @label.name
      old_desc = @label.description
      actor_id = GitHub.context[:actor_id] || User.ghost.id
      @label.update!(name: "new-name", color: "ffffff", description: "new-desc")

      assert event = events.pop, "a label.update event was expected"
      assert_equal @label.id, event.payload[:label_id]
      assert_equal actor_id, event.payload[:actor_id]
      assert_equal old_name, event.payload[:changes][:old_name]
      assert_equal old_color, event.payload[:changes][:old_color]
      assert_equal old_desc, event.payload[:changes][:old_description]
    end
  end

  test "async_target_for_conditional_access returns the repo's TFCA" do
    async_tfca = @label.async_target_for_conditional_access
    assert_equal @label.repository.owner, async_tfca.sync
  end

  context "re-indexes issues in search after updating name" do
    context "ReindexIssuesForAssociationJob" do
      test "doesn't re-index if name hasn't changed" do
        GitHub.context.push(actor_id: @user.id)
        Issues::ReindexIssuesForAssociationJob.expects(:enqueue).never

        @label.updated_at = Time.now + 1.hour
        @label.save!
      end

      test "enqueues bulk queue job if name has changed" do
        GitHub.context.push(actor_id: @user.id)
        Issues::ReindexIssuesForAssociationJob.expects(:enqueue).with(:labels, @label.id).returns(nil).once

        @label.name = "#{@label.name}-renamed"
        @label.save!
      end
    end
  end

  test "is deleted with repository" do
    other_label = create :label

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = @repo
      config.expect_destroyed = [@label]
      config.expect_not_destroyed = [other_label]
    end
  end
end
