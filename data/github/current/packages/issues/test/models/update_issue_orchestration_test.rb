# typed: true
# frozen_string_literal: true

require "test_helper"

class UpdateIssueOrchestrationTest < GitHub::TestCase
  include DogstatsTestHelpers
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, has_discussions: true)
    @issue = create(:issue, :wait_for_orchestration, repository: @repo, user: @user)
    DUMMY_WEBHOOK_PAYLOAD = {
      issue_id: @issue.id,
      repo: @issue.repository.name_with_display_owner,
      repo_id: @issue.repository_id,
      public_repo: @issue.repository.public?,
      user: @issue.user.display_login,
      user_id: @issue.user_id,
      actor: @user.display_login,
      actor_id: @user.id,
      assignee_ids: [@user.id],
      spammy: false,
      allowed: true,
    }.freeze
  end

  test "Validates and runs orchestration when saving an existing object" do
    perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
      @issue.save!
    end

    orchestration = IssueOrchestration.find_by(issue_id: @issue.id, type: "UpdateIssueOrchestration")
    refute_nil orchestration
    assert_equal :succeeded, T.must(orchestration).state.to_sym
    assert_equal @issue.id, T.must(orchestration).issue_id
    assert_equal @issue.repository, T.must(orchestration).repository
  end

  test "Validates and runs orchestration when touching an object" do
    perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
      @issue.touch
    end

    orchestration = IssueOrchestration.find_by(issue_id: @issue.id, type: "UpdateIssueOrchestration")
    refute_nil orchestration
    assert_equal :succeeded, T.must(orchestration).state.to_sym
    assert_equal @issue.id, T.must(orchestration).issue_id
    assert_equal @issue.repository, T.must(orchestration).repository
  end

  test "Doesn't run on issue creation" do
    UpdateIssueOrchestration.any_instance.expects(:validate!).never
    orchestration = IssueOrchestration.find_by(issue_id: @issue.id, type: "UpdateIssueOrchestration")
    assert_nil orchestration
  end

  test "Can run multiple updates at the same time" do
    2.times do
      orchestration = T.must(IssueOrchestration.update_issue!(issue: @issue, actor: @user))
      orchestration.state = "running".to_sym
      orchestration.save!
    end
  end

  test "creates a single update orchestration for multiple updates inside a transaction" do
    perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
      Issue.transaction do
        @issue.title = "ABC"
        @issue.save!

        @issue.title = "DEF"
        @issue.save!
      end
    end

    orchestrations = IssueOrchestration.where(issue_id: @issue.id, type: "UpdateIssueOrchestration").to_a
    assert_equal 1, orchestrations.size
    assert_predicate orchestrations.first, :succeeded?
  end

  test "can run all async steps when issue is deleted" do
    UpdateIssueOrchestration.any_instance.stubs(:execute).returns(true)

    @issue.title = "My new shiny title"
    @issue.save!

    orchestration = T.must(IssueOrchestration.find_by(issue_id: @issue.id, type: "UpdateIssueOrchestration"))
    assert_equal :created, orchestration.state.to_sym

    @issue.destroy!

    UpdateIssueOrchestration.any_instance.unstub(:execute)

    orchestration.execute(synchronous: true)
    assert_equal :succeeded, orchestration.reload.state.to_sym
  end

  context "#set_assignees" do
    test "sets assignees via orchestration" do
      assert @issue.assignees.empty?

      new_assignee_ids = [@user.id]
      4.times do
        user = create(:user)
        @repo.add_member(user)
        new_assignee_ids << user.id
      end

      update_issue_orchestration = IssueOrchestration.update_issue!(actor: @user, issue: @issue)
      update_issue_orchestration.data[:assignee_data] = { user_assignee_ids: new_assignee_ids }
      update_issue_orchestration.execute!

      assert @issue.reload.assignees.pluck(:id).sort, new_assignee_ids.sort
    end

    test "sets issue_changed when assignees updated" do
      assert @issue.assignees.empty?

      update_issue_orchestration = IssueOrchestration.update_issue!(actor: @user, issue: @issue)
      update_issue_orchestration.data[:assignee_data] = { user_assignee_ids: [@user.id] }
      update_issue_orchestration.execute!

      assert_equal true, update_issue_orchestration.reload.data[:issue_changed]
    end

    test "sets issue_changed from false to true when assignees updated" do
      assert @issue.assignees.empty?

      update_issue_orchestration = IssueOrchestration.update_issue!(actor: @user, issue: @issue)
      update_issue_orchestration.data[:issue_changed] = false
      update_issue_orchestration.data[:assignee_data] = { user_assignee_ids: [@user.id] }
      update_issue_orchestration.execute!

      assert_equal true, update_issue_orchestration.reload.data[:issue_changed]
    end
  end

  context "#set_issue_changed" do
    test "sets issue_changed attribute when issue has been changed" do
      @issue.title = "New Title"
      update_issue_orchestration = IssueOrchestration.update_issue!(actor: @user, issue: @issue)
      update_issue_orchestration.execute!

      assert_equal true, update_issue_orchestration.reload.data[:issue_changed]
    end

    test "does not set issue_changed attribute when issue is unchanged" do
      update_issue_orchestration = IssueOrchestration.update_issue!(actor: @user, issue: @issue)
      update_issue_orchestration.execute!

      assert_equal true, update_issue_orchestration.reload.data.keys.exclude?(:issue_changed)
    end
  end

  context "#update_close_issue_references" do
    test "update close issue references via orchestration" do
      pull = perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        create(:pull_request, :disable_disk_access, body: "What am I supposed to fix?", repository: @repo)
      end

      UpdateCloseIssueReferencesJob.expects(:perform_later).once

      perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        pull.issue.body = "Now I know - it fixes ##{@issue.number}!"
        pull.issue.save!
      end

      orchestration = T.must(IssueOrchestration.find_by(issue_id: pull.issue.id, type: "UpdateIssueOrchestration"))

      assert orchestration.should_update_close_issue_references
      assert_equal :succeeded, orchestration.state.to_sym
    end

    test "does not update close issue references for issues in orchestration" do
      referencing_issue = create(:issue, :wait_for_orchestration, body: "I'm closing something too?", repository: @repo)

      UpdateCloseIssueReferencesJob.expects(:perform_later).never

      perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        referencing_issue.body = "Close ##{@issue.number}"
        referencing_issue.save!
      end

      orchestration = T.must(IssueOrchestration.find_by(issue_id: referencing_issue.id, type: "UpdateIssueOrchestration"))

      refute orchestration.should_update_close_issue_references # not a PR
      assert_equal :succeeded, orchestration.state.to_sym
    end

    test "does not update close issue references if importing via orchestration" do
      pull = perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        create(:importable_pull_request, :disable_disk_access, body: "What am I supposed to fix?", repository: @repo)
      end

      UpdateCloseIssueReferencesJob.expects(:perform_later).never

      perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        pull.issue.body = "Now I know - it fixes ##{@issue.number}!"
        pull.issue.save!
      end

      orchestration = T.must(IssueOrchestration.find_by(issue_id: pull.issue.id, type: "UpdateIssueOrchestration"))

      refute orchestration.should_update_close_issue_references # importing
      assert_equal :succeeded, orchestration.state.to_sym
    end

    context "#sync_pull_request_updated_at" do
      test "issue.touch: PR gets updated" do
        Timecop.freeze do
          pull = perform_enqueued_jobs only: [IssueOrchestration.job_class] do
            create(:pull_request, :disable_disk_access, body: "pickles", repository: @repo)
          end
          pull.update_attribute(:updated_at, 10.minutes.ago)
          issue = pull.issue

          updated_tables = log_updated_tables do
            perform_enqueued_jobs only: [IssueOrchestration.job_class] do
              issue.touch
            end
          end

          assert_equal %w[issues issue_orchestrations pull_requests], updated_tables.uniq
          assert_equal pull.reload.updated_at, issue.updated_at

          orchestration = T.must(UpdateIssueOrchestration.find_by(issue_id: issue.id))
          assert_equal :succeeded, orchestration.state.to_sym
        end
      end

      test "issue.update: PR gets updated" do
        Timecop.freeze do
          pull = perform_enqueued_jobs only: [IssueOrchestration.job_class] do
            create(:pull_request, :disable_disk_access, body: "pickles", repository: @repo)
          end
          pull.update_column(:updated_at, 10.minutes.ago)
          issue = pull.issue

          updated_tables = log_updated_tables do
            perform_enqueued_jobs only: [IssueOrchestration.job_class] do
              issue.update!(title: "pickles")
            end
          end

          assert_equal %w[issues issue_orchestrations pull_requests], updated_tables.uniq
          assert_equal pull.reload.updated_at, issue.updated_at

          orchestration = T.must(UpdateIssueOrchestration.find_by(issue_id: issue.id, type: "UpdateIssueOrchestration"))
          assert_equal :succeeded, orchestration.state.to_sym
        end
      end
    end
  end

  context "#instrument_update_event" do
    test "instruments when an issue's body is updated" do
      events = subscribe "issue.update"
      GitHub.context.push(actor_id: @user.id)

      previous_body = @issue.body

      perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        # Calling `update_body` will create two IssueEdits, a normal `update` call doesn't create any
        @issue.update_body("Changed Body", @user)
      end

      expected_payload = DUMMY_WEBHOOK_PAYLOAD.merge(
        old_body: previous_body,
        body: "Changed Body",
        org: nil,
        business: nil,
      ).merge(@issue.event_analytics_payload)

      assert event = events.pop, "not instrumented"
      assert_equal expected_payload.sort, event.payload.sort

      orchestration = T.must(UpdateIssueOrchestration.find_by(issue_id: @issue.id, type: "UpdateIssueOrchestration"))
      assert_equal :succeeded, orchestration.state.to_sym
    end

    test "instruments when an issue's title is updated" do
      events = subscribe "issue.update"
      GitHub.context.push(actor_id: @user.id)

      previous_title = @issue.title

      perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        @issue.update(title: "Changed Title")
      end

      expected_payload = DUMMY_WEBHOOK_PAYLOAD.merge(
        old_title: previous_title,
        title: "Changed Title",
        org: nil,
        business: nil,
      ).merge(@issue.event_analytics_payload)

      assert event = events.pop, "not instrumented"
      assert_equal expected_payload.sort, event.payload.sort

      orchestration = T.must(UpdateIssueOrchestration.find_by(issue_id: @issue.id, type: "UpdateIssueOrchestration"))
      assert_equal :succeeded, orchestration.state.to_sym
    end

    test "does not instrument an update when neither title or body has changed" do
      events = subscribe "issue.update"
      GitHub.context.push(actor_id: @user.id)

      assert @issue.open?
      perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        @issue.close!
      end

      assert events.empty?
      orchestration = T.must(UpdateIssueOrchestration.find_by(issue_id: @issue.id, type: "UpdateIssueOrchestration"))
      assert_equal :succeeded, orchestration.state.to_sym
    end

    test "instruments correctly when an issue's body is updated several times" do
      events = subscribe "issue.update"
      GitHub.context.push(actor_id: @user.id)

      3.times do |i|
        previous_body = @issue.body

        perform_enqueued_jobs only: [IssueOrchestration.job_class] do
          # Calling `update_body` will create two IssueEdits, a normal `update` call doesn't create any
          @issue.update_body("Changed Body ##{i}", @user)
        end

        expected_payload = DUMMY_WEBHOOK_PAYLOAD.merge(
          old_body: previous_body,
          body: "Changed Body ##{i}",
          org: nil,
          business: nil,
        ).merge(@issue.event_analytics_payload)

        assert event = events.pop, "not instrumented"
        assert_equal expected_payload.sort, event.payload.sort
      end
    end

    test "does not instrument when single IssueEdit exists instead of two" do
      assert IssueEdit.count, 0

      events = subscribe "issue.update"
      GitHub.context.push(actor_id: @user.id)

      previous_body = @issue.body

      # This will create two IssueEdits
      @issue.update_body("Changed Body", @user)

      assert IssueEdit.count, 2
      T.must(IssueEdit.first).destroy
      assert IssueEdit.count, 1

      perform_enqueued_jobs only: [IssueOrchestration.job_class]

      assert events.empty?
    end

    test "does not instrument when there are no IssueEdits" do
      assert IssueEdit.count, 0

      events = subscribe "issue.update"
      GitHub.context.push(actor_id: @user.id)

      previous_body = @issue.body

      # This will create two IssueEdits
      @issue.update_body("Changed Body", @user)

      assert IssueEdit.count, 2
      IssueEdit.destroy_all
      assert IssueEdit.count, 0

      perform_enqueued_jobs only: [IssueOrchestration.job_class]

      assert events.empty?
    end
  end

  context "#sync_memex_items_updated_at" do
    test "syncs memex items updated_at when issue changed" do
      assert_performed_jobs(1, only: [TouchMemexProjectItemsJob]) do
        perform_enqueued_jobs only: [IssueOrchestration.job_class] do
          @issue.update_body("Changed Body", @user)
        end
      end

      orchestration = T.must(UpdateIssueOrchestration.find_by(issue_id: @issue.id))
      assert_equal :succeeded, orchestration.state.to_sym
    end

    test "does not sync memex items updated_at when issue is unchanged" do
      assert_enqueued_jobs(0, only: [TouchMemexProjectItemsJob]) do
        perform_enqueued_jobs only: [IssueOrchestration.job_class] do
          @issue.save!
        end
      end

      orchestration = T.must(UpdateIssueOrchestration.find_by(issue_id: @issue.id))
      assert_equal :succeeded, orchestration.state.to_sym
    end
  end

  context "#attach_matching_assets" do
    test "does not attach matching assets as a part of orchestration when body unchanged" do
      Issue.any_instance.expects(:attach_matching_assets).never

      perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        @issue.update(title: "Changed Title")
      end

      orchestration = T.must(UpdateIssueOrchestration.find_by(issue_id: @issue.id))
      refute_nil orchestration
      assert_equal :succeeded, T.must(orchestration).state.to_sym
    end

    test "attaches matching assets as a part of orchestration when body changes" do
      Issue.any_instance.expects(:attach_matching_assets).once

      perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        @issue.update_body("Changed Body", @user)
      end

      orchestration = T.must(UpdateIssueOrchestration.find_by(issue_id: @issue.id))
      refute_nil orchestration
      assert_equal :succeeded, T.must(orchestration).state.to_sym
    end
  end
end

class UpdateIssueOrchestrationThreadedTest < GitHub::TestCase

  self.use_transactional_tests = false

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, has_discussions: true)
    @issue = create(:issue, :wait_for_orchestration, repository: @repo, user: @user)
  end

  test "sets assignees via orchestration using upsert - FF enabled" do
    GitHub.flipper[:use_upsert_to_prevent_conflicts].enable

    assert @issue.assignees.empty?

    new_assignee_ids = [@user.id]
    4.times do
      user = create(:user)
      @repo.add_member(user)
      new_assignee_ids << user.id
    end

    threads = []
    threads << Thread.new do
      Thread.current.abort_on_exception = true
      Issue.stubs(:save!).raises(ActiveRecord::RecordInvalid) do
        update_issue_orchestration = IssueOrchestration.update_issue!(actor: @user, issue: @issue)
        update_issue_orchestration.data[:assignee_data] = { user_assignee_ids: new_assignee_ids }
        update_issue_orchestration.execute!
      end
    end

    threads << Thread.new do
      GH::Context.enabled do
        Thread.current.abort_on_exception = true
        update_issue_orchestration = IssueOrchestration.update_issue!(actor: @user, issue: @issue)
        update_issue_orchestration.data[:assignee_data] = { user_assignee_ids: [@user.id] }
        update_issue_orchestration.execute!
      end
    end

    threads.each(&:join)

    assert_includes @issue.reload.assignees, @user
  end

  test "sets assignees via orchestration fails on conflict - FF disabled" do
    GitHub.flipper[:use_upsert_to_prevent_conflicts].disable

    assert @issue.assignees.empty?

    new_assignee_ids = [@user.id]
    4.times do
      user = create(:user)
      @repo.add_member(user)
      new_assignee_ids << user.id
    end

    @issue.stubs(:save!).raises(ActiveRecord::RecordInvalid).once

    assert_raises(ActiveRecord::RecordInvalid) do
      threads = []
      exceptions = []
      threads << Thread.new do
        GH::Context.enabled do
          Thread.current.abort_on_exception = true
          begin
            Issue.stubs(:save!).raises(ActiveRecord::RecordInvalid) do
              update_issue_orchestration = IssueOrchestration.update_issue!(actor: @user, issue: @issue)
              update_issue_orchestration.data[:assignee_data] = { user_assignee_ids: new_assignee_ids }
              update_issue_orchestration.execute!
            end
          rescue ActiveRecord::RecordInvalid => e
            exceptions << e
          end
        end
      end

      threads << Thread.new do
        GH::Context.enabled do
          Thread.current.abort_on_exception = true
          begin
            update_issue_orchestration = IssueOrchestration.update_issue!(actor: @user, issue: @issue)
            update_issue_orchestration.data[:assignee_data] = { user_assignee_ids: [@user.id] }
            update_issue_orchestration.execute!
          rescue ActiveRecord::RecordInvalid => e
            exceptions << e
          end
        end
      end

      threads.each(&:join)
      raise exceptions.pop unless exceptions.empty?
    end
  end
end
