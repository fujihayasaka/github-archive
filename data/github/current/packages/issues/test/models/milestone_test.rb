# typed: true
# frozen_string_literal: true

require "test_helper"

class MilestonesTest < GitHub::TestCase
  include HydroTestHelpers
  include StringFromBinaryTestHelper
  include BackgroundDeletesTestHelpers

  fixtures do
    @user = create(:user)
    @collab = create(:user)
    @rando = create(:user)
    @repo             = create(:repository, owner: @user)
    @repo2            = create(:repository)
    @milestone        = create :milestone, repository: @repo,
      created_by: @repo.owner,
      due_on: Time.now + 1.month,
      title: "The Milestone"
    @milestone2       = create :milestone, repository: @repo, created_by: @repo.owner, due_on: Time.now + 1.month
    @milestone3       = create :milestone, repository: @repo2, created_by: @repo2.owner, due_on: Time.now + 1.month
    @closed_milestone = create :milestone, repository: @repo, created_by: @repo.owner, due_on: Time.now + 1.month, state: "closed"
    @open_issue       = create :issue, repository: @repo, user: @repo.owner, milestone: @milestone
    @closed_issue     = create :issue, repository: @repo, user: @repo.owner, state: "closed", milestone: @milestone
    @repo.add_member(@collab, action: :write)
  end

  test "milestones require a title" do
    assert @milestone.valid?
    @milestone.title = nil
    assert !@milestone.valid?
  end

  test "milestones require a title less then 255" do
    assert_predicate @milestone, :valid?
    @milestone.title = "Longer than 255 Lorem ipsum dolor sit amet, nonummy ligula volutpat hac integer nonummy. Suspendisse ultricies, congue etiam tellus, erat libero, nulla eleifend, mauris pellentesque. Suspendisse integer praesent vel, integer gravida mauris, fringilla vehicula lacinia non"
    refute_predicate @milestone, :valid?
    assert_equal ["is too long (maximum is 255 characters)"], @milestone.errors[:title]
  end

  test "milestones require a unique title, per repository" do
    assert @milestone.valid?
    assert_raises ActiveRecord::RecordInvalid do
      create :milestone, repository: @repo, title: @milestone.title
    end
    create :milestone, repository: @repo, title: @milestone.title + SecureRandom.hex

    milestone = create :milestone, repository: @repo, title: @milestone.title.upcase
    assert milestone.valid?
  end

  [:description, :title].each do |field|
    test "#{field} after typecast" do
      milestone = create(:milestone,
        repository: @repo,
        title: "Revisi\xC3\xB3n 10 de junio del 2016",
        description: "Revisi\xC3\xB3n 10 de junio del 2016",
      ).reload

      assert_equal milestone.read_attribute(field).encoding, Encoding::UTF_8
      assert_equal milestone.send(field).encoding, Encoding::UTF_8
    end
  end

  [:description, :title].each do |field|
    test "supports emoji for #{field}" do
      milestone = create(:milestone, field => "we ❤️ emojis")

      assert_multibyte_tracked_changes(milestone, field)
    end
  end

  test "milestones require a repository" do
    assert @milestone.valid?
    @milestone.repository_id = nil
    assert !@milestone.valid?
  end

  test "milestones require created_by be set" do
    assert @milestone.valid?
    @milestone.created_by_id = nil
    assert !@milestone.valid?
  end

  test "milestones require due date to be in range that MySQL can handle" do
    assert_predicate @milestone, :valid?

    @milestone.due_on = "1899-12-31"
    refute_predicate @milestone, :valid?
    assert_includes @milestone.errors.full_messages, "Due date must be between year 1900 and 2999"

    @milestone.due_on = "3000-01-01"
    refute_predicate @milestone, :valid?
    assert_includes @milestone.errors.full_messages, "Due date must be between year 1900 and 2999"

    @milestone.due_on = "2021-12-31"
    assert_predicate @milestone, :valid?

    @milestone.due_on = "1900-01-01"
    assert_predicate @milestone, :valid?

    @milestone.due_on = "2999-12-31"
    assert_predicate @milestone, :valid?
  end

  test "milestone completeness sort" do
    repo        = create(:repository)
    empty       = create(:milestone, repository: repo, created_by: repo.owner, open_issue_count: 0, closed_issue_count: 0)
    one_hundred = create(:milestone, repository: repo, created_by: repo.owner, open_issue_count: 2, closed_issue_count: 2)
    partial     = create(:milestone, repository: repo, created_by: repo.owner, open_issue_count: 3, closed_issue_count: 1)

    assert_equal [one_hundred, partial, empty], repo.milestones.sorted_by("completeness", "desc")
    assert_equal [empty, partial, one_hundred], repo.milestones.sorted_by("completeness", "asc")
  end

  test "milestones can be sorted using due_date / due_on" do
    repo  = create(:repository)
    three = create :milestone, repository: repo, created_by: repo.owner, due_on: 3.weeks.from_now
    two   = create :milestone, repository: repo, created_by: repo.owner, due_on: 2.weeks.from_now
    one   = create :milestone, repository: repo, created_by: repo.owner, due_on: 1.week.from_now

    assert_equal [one, two, three], repo.milestones.sorted_by("due_date", "asc")
    assert_equal [three, two, one], repo.milestones.sorted_by("due_date", "desc")

    # "due_on" is the documented default when listing milestones via REST API
    assert_equal [one, two, three], repo.milestones.sorted_by("due_on", "asc")
    assert_equal [three, two, one], repo.milestones.sorted_by("due_on", "desc")
  end

  test "milestones have a url" do
    assert_equal "#{@repo.permalink}/milestones/#{UrlHelper.escape_path(@milestone.title)}", @milestone.url
  end

  test "milestones urls ignore dynamic_lab? with allow_temporary_subdomains: true" do
    GitHub.stubs(:dynamic_lab?).returns(true)

    with_global_host_name("lerebear.review-lab.github.com") do
      assert_equal "#{@repo.permalink}/milestones/#{UrlHelper.escape_path(@milestone.title)}", @milestone.url
    end
  end

  test "milestone urls honor allow_temporary_subdomains: false" do
    GitHub.stubs(:dynamic_lab?).returns(true)

    with_global_host_name("lerebear.review-lab.github.com") do
      expected_url = "https://github.com/#{@repo.owner.name}/#{@repo.name}/milestones/#{UrlHelper.escape_path(@milestone.title)}"
      actual_url = @milestone.url(allow_temporary_subdomains: false)
      assert_equal expected_url, actual_url
    end
  end

  test "milestones should have many issues" do
    assert @milestone.issues.include?(@open_issue)
    assert @milestone.issues.include?(@closed_issue)
  end

  test "milestones should belong to a repository" do
    assert_equal @repo, @milestone.repository
  end

  test "milestones should track who created them" do
    assert_equal @repo.owner, @milestone.created_by
  end

  test "milestones can have a due date" do
    assert @milestone.due_on.is_a?(Time)
  end

  test "milestones have an incrementing number scoped by repository, just like issues" do
    assert_equal 1, @milestone.number
    assert_equal 2, @milestone2.number
    assert_equal 1, @milestone3.number
  end

  test "milestone state defaults to 'open'" do
    assert_equal "open", @milestone.state
  end

  test "milestone state can only be 'open' or 'closed'" do
    assert @milestone.valid?
    @milestone.state = "closed"
    assert @milestone.valid?
    @milestone.state = "finna"
    assert !@milestone.valid?
  end

  test "knows its next state" do
    assert_equal "closed", @milestone.next_state
    @milestone.state = "closed"
    assert_equal "open", @milestone.next_state
  end

  test "milestone knows when it was closed" do
    Timecop.freeze do
      assert_nil @milestone.closed_at
      @milestone.toggle_state!
      assert_kind_of Time, @milestone.reload.closed_at
      assert_equal @milestone.updated_at, @milestone.closed_at
    end
  end

  test "can toggle the state of a milestone" do
    assert_nil @milestone.closed_at
    assert @milestone.toggle_state!
    refute_nil @milestone.reload.closed_at
    assert_equal "closed", @milestone.state
  end

  test "adding or removing issues should update open_issue_count and closed_issue_count" do
    assert @open_issue.open?
    assert @closed_issue.closed?

    @open_issue.milestone = @milestone
    @closed_issue.milestone = @milestone

    @open_issue.save
    @closed_issue.save

    open_before = @milestone.open_issue_count
    closed_before = @milestone.closed_issue_count

    @open_issue.milestone = nil
    @open_issue.save
    @milestone.reload
    assert_equal open_before -= 1, @milestone.open_issue_count
    assert_equal closed_before, @milestone.closed_issue_count

    @closed_issue.milestone = nil
    @closed_issue.save
    @milestone.reload
    assert_equal open_before, @milestone.open_issue_count
    assert_equal closed_before -= 1, @milestone.closed_issue_count

    @open_issue.milestone = @milestone
    @open_issue.save
    @milestone.reload
    assert_equal open_before + 1, @milestone.open_issue_count
    assert_equal closed_before, @milestone.closed_issue_count

    @milestone.reload
    open_before = @milestone.open_issue_count
    closed_before = @milestone.closed_issue_count
    open_before2 = @milestone2.open_issue_count
    closed_before2 = @milestone2.closed_issue_count

    @open_issue.milestone = @milestone2
    @open_issue.save
    @milestone2.reload
    @milestone.reload
    assert_equal open_before - 1, @milestone.open_issue_count
    assert_equal closed_before, @milestone.closed_issue_count
    assert_equal open_before2 + 1, @milestone2.open_issue_count
    assert_equal closed_before, @milestone2.closed_issue_count
  end

  test "should have a scope for all open milestones" do
    milestones = Milestone.open_milestones.all
    assert milestones.include? @milestone
    assert milestones.include? @milestone2
  end

  test "should have a scope for all closed milestones" do
    assert_equal Milestone.closed_milestones.all, [@closed_milestone]
  end

  test "should be past due if due_date is in the past" do
    @milestone.due_on = Time.now - 1.month
    assert @milestone.past_due?
  end

  test "should not be past due on the same date" do
    @milestone.due_on = Time.zone.local(2014, 3, 15)

    Time.use_zone "Australia/Melbourne" do
      Timecop.freeze(Time.zone.local(2014, 3, 15, 2)) do
        assert !@milestone.past_due?
      end
    end
    Time.use_zone "Europe/Amsterdam" do
      Timecop.freeze(Time.zone.local(2014, 3, 15, 2)) do
        assert !@milestone.past_due?
      end
    end
    Time.use_zone "America/Los_Angeles" do
      Timecop.freeze(Time.zone.local(2014, 3, 15, 2)) do
        assert !@milestone.past_due?
      end
    end
  end

  test "should be past due on the next day" do
    @milestone.due_on = Time.zone.local(2014, 3, 15)

    Time.use_zone "Australia/Melbourne" do
      Timecop.freeze(Time.zone.local(2014, 3, 16)) do
        assert_predicate @milestone, :past_due?
      end
    end
    Time.use_zone "Europe/Amsterdam" do
      Timecop.freeze(Time.zone.local(2014, 3, 16)) do
        assert_predicate @milestone, :past_due?
      end
    end
    Time.use_zone "America/Los_Angeles" do
      Timecop.freeze(Time.zone.local(2014, 3, 16)) do
        assert_predicate @milestone, :past_due?
      end
    end
  end

  test "should not be past due on the same calendar day" do
    @milestone.due_on = Time.zone.local(2014, 3, 15)

    Time.use_zone "Australia/Melbourne" do
      Timecop.freeze(Time.zone.local(2014, 3, 15, 23)) do
        refute_predicate @milestone, :past_due?
      end
    end
    Time.use_zone "Europe/Amsterdam" do
      Timecop.freeze(Time.zone.local(2014, 3, 15, 23)) do
        refute_predicate @milestone, :past_due?
      end
    end
    Time.use_zone "America/Los_Angeles" do
      Timecop.freeze(Time.zone.local(2014, 3, 15, 23)) do
        refute_predicate @milestone, :past_due?
      end
    end
  end

  test "#due_on= with empty values" do
    @milestone.due_on = nil
    assert_nil @milestone.due_on
    @milestone.due_on = ""
    assert_nil @milestone.due_on
  end

  test "#due_on= with String" do
    @milestone.due_on = "2015-01-01"
    assert_equal Date.new(2015, 1, 1).to_time(:utc), @milestone.due_on
  end

  test "#due_on= with invalid String" do
    @milestone.due_on = "foobar"
    assert_nil @milestone.due_on
  end

  test "#due_on= with Date" do
    date = Date.new(2015, 1, 1)
    @milestone.due_on = date
    assert_equal date.to_time(:utc), @milestone.due_on
  end

  test "#due_on= with DateTime" do
    time = Date.new(2015, 1, 1).to_time(:utc)
    @milestone.due_on = time
    assert_equal time, @milestone.due_on
  end

  test_zones = ActiveSupport::TimeZone.all.uniq(&:utc_offset)

  test_zones.each do |zone|
    test_zones.each do |viewer_zone|
      test "returns a consistent #due_date when set in #{zone} and viewed in #{viewer_zone}" do
        date = Date.new(2014, 12, 4)
        Time.use_zone(zone) do
          Timecop.freeze Time.local(2014, 12, 1) do
            @milestone.due_on = date.beginning_of_day
          end
        end
        Time.use_zone(viewer_zone) do
          Timecop.freeze Time.local(2014, 12, 1) do
            assert_equal date, @milestone.due_date,
              "Midnight in #{viewer_zone} is #{date.beginning_of_day.utc}\nLocal Time is #{Time.current}"
          end
        end
      end
    end
  end

  test "generates events and unlinks issues in the background when destroyed" do
    open_milestone_issues = [
      @open_issue,
      create(:issue, repository: @repo, milestone: @milestone)
    ]
    milestone_issues = open_milestone_issues + [@closed_issue]
    assert milestone_issues.all? { |i| i.milestone_id == @milestone.id }

    GitHub.context.push(actor_id: @user.id)
    perform_enqueued_jobs(only: [NullifyMilestoneIdReferencesJob]) { @milestone.destroy }

    milestone_issues.each(&:reload)

    assert milestone_issues.all? { |i| i.milestone_id.nil? }
    assert open_milestone_issues.all? { |i| i.events.last.event == "demilestoned" && i.events.last.actor == @user }
    refute @closed_issue.events.any? { |e| e.event == "demilestoned" }
  end

  test "instruments a hydro update event for a change to title" do
    GitHub.context.push(actor_id: @user.id)

    previous_title = @milestone.title

    @milestone.update!(title: "#{previous_title} and more!")

    assert_hydro_published(
      {
        actor: Hydro::EntitySerializer.user(@user),
        milestone: Hydro::EntitySerializer.milestone(@milestone),
        previous_description: @milestone.description,
        previous_due_on: @milestone.due_on,
        previous_state: @milestone.state,
        previous_title: previous_title,
      },
      schema: "github.v1.MilestoneUpdate"
    )
  end

  test "instruments a hydro update event when description changes from some non-nil value to another" do
    GitHub.context.push(actor_id: @user.id)

    previous_description = @milestone.description
    refute_nil @milestone.description

    @milestone.update!(description: "#{previous_description} and more!")

    assert_hydro_published(
      {
        actor: Hydro::EntitySerializer.user(@user),
        milestone: Hydro::EntitySerializer.milestone(@milestone),
        previous_description: previous_description,
        previous_due_on: @milestone.due_on,
        previous_state: @milestone.state,
        previous_title: @milestone.title,
      },
      schema: "github.v1.MilestoneUpdate"
    )
  end

  test "instruments a hydro update event when description is first set" do
    GitHub.context.push(actor_id: @user.id)

    milestone_without_description = create(:milestone, description: nil)
    milestone_without_description.update!(description: "a big goal")

    assert_hydro_published(
      {
        actor: Hydro::EntitySerializer.user(@user),
        milestone: Hydro::EntitySerializer.milestone(milestone_without_description),
        previous_description: nil,
        previous_due_on: milestone_without_description.due_on,
        previous_state: milestone_without_description.state,
        previous_title: milestone_without_description.title,
      },
      schema: "github.v1.MilestoneUpdate"
    )
  end

  test "instruments a hydro update event for a change to state" do
    GitHub.context.push(actor_id: @user.id)

    previous_state = @milestone.state
    next_state = @milestone.next_state
    refute_equal previous_state, next_state

    @milestone.update!(state: next_state)

    assert_hydro_published(
      {
        actor: Hydro::EntitySerializer.user(@user),
        milestone: Hydro::EntitySerializer.milestone(@milestone),
        previous_description: @milestone.description,
        previous_due_on: @milestone.due_on,
        previous_state: previous_state,
        previous_title: @milestone.title,
      },
      schema: "github.v1.MilestoneUpdate"
    )
  end

  test "instruments a hydro update event when due_on changes from a non-nil value to another non-nil value" do
    GitHub.context.push(actor_id: @user.id)

    previous_due_on = @milestone.due_on
    next_due_on = Time.now
    refute_equal previous_due_on, next_due_on

    @milestone.update!(due_on: next_due_on)

    assert_hydro_published(
      {
        actor: Hydro::EntitySerializer.user(@user),
        milestone: Hydro::EntitySerializer.milestone(@milestone),
        previous_description: @milestone.description,
        previous_due_on: previous_due_on,
        previous_state: @milestone.state,
        previous_title: @milestone.title,
      },
      schema: "github.v1.MilestoneUpdate"
    )
  end

  test "instruments a hydro update event when due_on is first set" do
    GitHub.context.push(actor_id: @user.id)

    milestone_without_due_date = create(:milestone, due_on: nil)
    milestone_without_due_date.update!(due_on: Time.now)

    assert_hydro_published(
      {
        actor: Hydro::EntitySerializer.user(@user),
        milestone: Hydro::EntitySerializer.milestone(milestone_without_due_date),
        previous_description: milestone_without_due_date.description,
        previous_due_on: nil,
        previous_state: milestone_without_due_date.state,
        previous_title: milestone_without_due_date.title,
      },
      schema: "github.v1.MilestoneUpdate"
    )
  end

  test "can instrument a hydro update event that captures several simultaneous changes" do
    GitHub.context.push(actor_id: @user.id)

    previous_title = @milestone.title
    previous_state = @milestone.state
    next_state = @milestone.next_state
    refute_equal previous_state, next_state

    @milestone.update!(title: "#{previous_title} and more!", state: next_state)

    assert_hydro_published(
      {
        actor: Hydro::EntitySerializer.user(@user),
        milestone: Hydro::EntitySerializer.milestone(@milestone),
        previous_description: @milestone.description,
        previous_due_on: @milestone.due_on,
        previous_state: previous_state,
        previous_title: previous_title,
      },
      schema: "github.v1.MilestoneUpdate"
    )
  end

  test "does not instrument a hydro update event for an irrelevant attribute" do
    refute_includes Milestone::HYDRO_UPDATE_EVENT_ATTRIBUTES, :open_issue_count
    @milestone.update!(open_issue_count: @milestone.open_issue_count + 1)
    refute_hydro_messages(schema: "github.v1.MilestoneUpdate")
  end

  test "instruments a hydro event when the milestone is deleted" do
    GitHub.context.push(actor_id: @user.id)

    doomed_milestone = create(:milestone)
    doomed_milestone.destroy!

    assert_hydro_published(
      {
        actor: Hydro::EntitySerializer.user(@user),
        milestone: Hydro::EntitySerializer.milestone(doomed_milestone),
      },
      schema: "github.v1.MilestoneDelete"
    )
  end

  test "doesn't prevent issues from being closed after the milestone is destroyed" do
    perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { @milestone.destroy }
    @open_issue.close!
    assert @open_issue.closed?
  end

  test "it is GitHub::UserContent compatible" do
    assert_respond_to @milestone, :body
    assert_respond_to @milestone, :body_html
  end

  test "have an url" do
    assert_equal "#{GitHub.url}/#{@repo.owner.login}/#{@repo.name}/milestones/#{UrlHelper.escape_path(@milestone.title)}",
      @milestone.url
  end

  context "#memex_column_hash" do
    test "returns hash representation of a milestone" do
      assert_equal(
        {
          id: @milestone.id,
          number: @milestone.number,
          state: "open",
          title: "The Milestone",
          url: "/#{@milestone.repository.nwo}/milestone/#{@milestone.number}",
          dueDate: @milestone.due_date,
          repoNameWithOwner: @milestone.repository.nwo
        },
        @milestone.memex_column_hash
      )
    end
  end

  context "#memex_suggestion_hash" do
    test "returns hash representation of milestone" do
      assert_equal(
        {
          id: @milestone.id,
          number: @milestone.number,
          selected: true,
          state: "open",
          title: "The Milestone",
          url: "/#{@milestone.repository.nwo}/milestone/#{@milestone.number}",
          dueDate: @milestone.due_date,
          repoNameWithOwner: @milestone.repository.nwo
        },
        @milestone.memex_suggestion_hash(selected: true)
      )
    end
  end

  test "async_target_for_conditional_access returns the repo's TFCA" do
    async_tfca = @milestone.async_target_for_conditional_access
    assert_equal @milestone.repository.owner, async_tfca.sync
  end

  context "use 'Sequence' for number generation" do
    test "sequence milestone record is updated when milestones are created" do
      new_milestone = create :milestone, repository: @repo, created_by: @repo.owner, due_on: Time.now + 1.month

      assert_equal new_milestone.number, Sequence.get(new_milestone)

      # sanity check that we use the correct sequence table.
      sequence_number = T.must(RepositoryMilestonesSequence.find_by(repository_id: @repo.id)).number
      assert_equal new_milestone.number, sequence_number
    end

    test "deleting the latest milestone will not give the next milestone the same number" do
      new_milestone = create :milestone, repository: @repo, created_by: @repo.owner, due_on: Time.now + 1.month
      new_milestone_number = new_milestone.number

      new_milestone.destroy!

      deleted_milestone_number = new_milestone.number

      another_new_milestone = create :milestone, repository: @repo, created_by: @repo.owner, due_on: Time.now + 1.month
      assert_equal another_new_milestone.number, deleted_milestone_number + 1

      assert_equal another_new_milestone.number, Sequence.get(new_milestone)
    end
  end

  context "re-indexes issues in search after updating title" do
    context "ReindexIssuesForAssociationJob" do
      test "doesn't re-index if title hasn't changed" do
        GitHub.context.push(actor_id: @user.id)
        Issues::ReindexIssuesForAssociationJob.expects(:enqueue).never

        @milestone.updated_at = Time.now + 1.hour
        @milestone.save!
      end

      test "enqueues bulk queue job if title has changed" do
        GitHub.context.push(actor_id: @user.id)
        Issues::ReindexIssuesForAssociationJob.expects(:enqueue).with(:milestone, @milestone.id).returns(nil).once

        @milestone.title = "#{@milestone.title}-renamed"
        @milestone.save!
      end
    end
  end

  context "#async_closable_by?" do
    test "true for user with write access" do
      actor = create(:verified_user)
      @repo.add_member(actor, action: :write)
      assert @milestone.async_closable_by?(actor).sync
    end

    test "false for user without write access" do
      rando = create(:verified_user)
      refute @milestone.async_closable_by?(rando).sync
    end

    test "false for nil user" do
      refute @milestone.async_closable_by?(nil).sync
    end
  end

  context "#async_reopenable_by?" do
    test "true for user with write access" do
      assert @milestone.async_closable_by?(@collab).sync
    end

    test "false for user without write access" do
      refute @milestone.async_closable_by?(@rando).sync
    end

    test "false for nil user" do
      refute @milestone.async_closable_by?(nil).sync
    end
  end

  test "is deleted with repository" do
    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = @repo
      config.expect_destroyed = [@milestone, @milestone2, @closed_milestone]
      config.expect_not_destroyed = [@milestone3]
    end
  end
end
