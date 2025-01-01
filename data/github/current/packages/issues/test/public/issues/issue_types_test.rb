# typed: true
# frozen_string_literal: true

require "test_helper"

class Issues::Domain::IssueTypesTest < GitHub::TestCase
  fixtures do
    enable_feature_flag(:issue_types)
    @admin = create(:user, login: "org-owner")
    @original_org = create(:organization, admin: @admin)
    @repo = create(:repository, owner: @original_org)
    @original_org_first_type = @original_org.issue_types.find_by(name: IssueType::DEFAULTS.first[:name])
    @original_org_second_type = @original_org.issue_types.find_by(name: IssueType::DEFAULTS.second[:name])
    @original_org_custom_type = create(:issue_type, name: "Super secret type", owner: @original_org)
    @first_typed_issue_1 = create(:issue, repository: @repo, issue_type: @original_org_first_type)
    @first_typed_issue_2 = create(:issue, repository: @repo, issue_type: @original_org_first_type)
    @second_typed_issue = create(:issue, repository: @repo, issue_type: @original_org_second_type)
    @custom_typed_issue = create(:issue, repository: @repo, issue_type: @original_org_custom_type)
    @new_org = create(:organization, admin: @admin)
    @new_org_first_type = @new_org.issue_types.find_by(name: IssueType::DEFAULTS.first[:name])
    @new_org_second_type = @new_org.issue_types.find_by(name: IssueType::DEFAULTS.second[:name])
    @new_org_second_type.update(name: IssueType::DEFAULTS.second[:name].upcase)
  end

  setup do
    @domain = Issues::Domain::IssueTypes.new
  end

  context "transfer_issue_types_for_repo" do
    test "correctly transfers any issue types with the same name (case insensitive) to matching types in the new org" do
      freeze_time do
        timestamp = Timestamp.from_time(Time.now)
        assert_enqueued_jobs 1, only: AddToSearchIndexJob do
          assert_enqueued_with(
            job: AddToSearchIndexJob,
            args: ["issue", @custom_typed_issue.id, { "submitted_at" => timestamp, "guid" => AddToSearchIndexJob.guid("issue", @custom_typed_issue.id) }]
          ) do
            @domain.transfer_issue_types_for_repo(repo_id: @repo.id, old_owner: @original_org, new_owner: @new_org, actor: @admin)
          end
        end
      end

      assert_equal @first_typed_issue_1.reload.issue_type, @new_org_first_type
      assert_equal @first_typed_issue_2.reload.issue_type, @new_org_first_type
      assert_equal @second_typed_issue.reload.issue_type, @new_org_second_type
      refute @custom_typed_issue.reload.issue_type
    end

    test "correctly destroys types if they are disabled for the old org" do
      @original_org_first_type.update(enabled: false)
      freeze_time do
        timestamp = Timestamp.from_time(Time.now)
        assert_enqueued_jobs 3, only: AddToSearchIndexJob do
          assert_enqueued_with(
            job: AddToSearchIndexJob,
            args: ["issue", @first_typed_issue_1.id, { "submitted_at" => timestamp, "guid" => AddToSearchIndexJob.guid("issue", @first_typed_issue_1.id) }]
          ) do
            assert_enqueued_with(
              job: AddToSearchIndexJob,
              args: ["issue", @first_typed_issue_2.id, { "submitted_at" => timestamp, "guid" => AddToSearchIndexJob.guid("issue", @first_typed_issue_2.id) }]
            ) do
              assert_enqueued_with(
                job: AddToSearchIndexJob,
                args: ["issue", @custom_typed_issue.id, { "submitted_at" => timestamp, "guid" => AddToSearchIndexJob.guid("issue", @custom_typed_issue.id) }]
              ) do

                @domain.transfer_issue_types_for_repo(repo_id: @repo.id, old_owner: @original_org, new_owner: @new_org, actor: @admin)
              end
            end
          end
        end
      end

      refute @first_typed_issue_1.reload.issue_type
      refute @first_typed_issue_2.reload.issue_type
    end

    test "correctly destroys types if they are disabled for the new org" do
      @new_org_first_type.update(enabled: false)
      freeze_time do
        timestamp = Timestamp.from_time(Time.now)
        assert_enqueued_jobs 3, only: AddToSearchIndexJob do
          assert_enqueued_with(
            job: AddToSearchIndexJob,
            args: ["issue", @first_typed_issue_1.id, { "submitted_at" => timestamp, "guid" => AddToSearchIndexJob.guid("issue", @first_typed_issue_1.id) }]
          ) do
            assert_enqueued_with(
              job: AddToSearchIndexJob,
              args: ["issue", @first_typed_issue_2.id, { "submitted_at" => timestamp, "guid" => AddToSearchIndexJob.guid("issue", @first_typed_issue_2.id) }]
            ) do
              assert_enqueued_with(
                job: AddToSearchIndexJob,
                args: ["issue", @custom_typed_issue.id, { "submitted_at" => timestamp, "guid" => AddToSearchIndexJob.guid("issue", @custom_typed_issue.id) }]
              ) do

                @domain.transfer_issue_types_for_repo(repo_id: @repo.id, old_owner: @original_org, new_owner: @new_org, actor: @admin)
              end
            end
          end
        end
      end

      refute @first_typed_issue_1.reload.issue_type
      refute @first_typed_issue_2.reload.issue_type
    end

    test "destroys all issue types if new org has no types" do
      @new_org.issue_types.destroy_all
      freeze_time do
        timestamp = Timestamp.from_time(Time.now)
        assert_enqueued_jobs 4, only: AddToSearchIndexJob do
          @domain.transfer_issue_types_for_repo(repo_id: @repo.id, old_owner: @original_org, new_owner: @new_org, actor: @admin)
        end
      end

      refute @first_typed_issue_1.reload.issue_type
      refute @first_typed_issue_2.reload.issue_type
      refute @second_typed_issue.reload.issue_type
      refute @custom_typed_issue.reload.issue_type
    end

    test "destroys all issue types if new owner is a user" do
      freeze_time do
        timestamp = Timestamp.from_time(Time.now)
        assert_enqueued_jobs 4, only: AddToSearchIndexJob do
          @domain.transfer_issue_types_for_repo(repo_id: @repo.id, old_owner: @original_org, new_owner: @admin, actor: @admin)
        end
      end

      refute @first_typed_issue_1.reload.issue_type
      refute @first_typed_issue_2.reload.issue_type
      refute @second_typed_issue.reload.issue_type
      refute @custom_typed_issue.reload.issue_type
    end

    test "does nothing if old_owner is a user" do
      assert_enqueued_jobs 0, only: AddToSearchIndexJob do
        @domain.transfer_issue_types_for_repo(repo_id: @repo.id, old_owner: @admin, new_owner: @new_org, actor: @admin)
      end

      assert_equal @first_typed_issue_1.reload.issue_type, @original_org_first_type
      assert_equal @first_typed_issue_2.reload.issue_type, @original_org_first_type
      assert_equal @second_typed_issue.reload.issue_type, @original_org_second_type
      assert_equal @custom_typed_issue.reload.issue_type, @original_org_custom_type
    end

    test "doesn't destroy issue type if the issue already matches the new owner" do
      @first_typed_issue_1.update_column(:issue_type_id, @new_org_first_type.id)
      @domain.transfer_issue_types_for_repo(repo_id: @repo.id, old_owner: @original_org, new_owner: @new_org, actor: @admin)

      assert_equal @first_typed_issue_1.reload.issue_type, @new_org_first_type
    end

    test "destroys any issue type events" do
      added_event = create(:issue_event,
        issue:  @first_typed_issue_1,
        event:  "issue_type_added",
        issue_type_id: @original_org_first_type.id,
        issue_type_name: @original_org_first_type.name,
        issue_type_color: @original_org_first_type.color
      )
      added_event_id = added_event.id

      removed_event = create(:issue_event,
        issue:  @first_typed_issue_1,
        event:  "issue_type_removed",
        prev_issue_type_name: @original_org_first_type.name,
        prev_issue_type_color: @original_org_first_type.color
      )
      removed_event_id = removed_event.id

      changed_event = create(:issue_event,
        issue:  @first_typed_issue_1,
        event: "issue_type_changed",
        issue_type_id: @original_org_first_type.id,
        issue_type_name: @original_org_first_type.name,
        issue_type_color: @original_org_first_type.color,
        prev_issue_type_id: @original_org_second_type.id,
        prev_issue_type_name: @original_org_second_type.name,
        prev_issue_type_color: @original_org_second_type.color,
      )
      changed_event_id = changed_event.id

      assigned_event = create(:issue_event,
        event: "assigned",
        issue: @first_typed_issue_1,
        actor: @admin,
        subject: @admin
      )
      assigned_event_id = assigned_event.id

      @domain.transfer_issue_types_for_repo(repo_id: @repo.id, old_owner: @original_org, new_owner: @new_org, actor: @admin)

      refute IssueEvent.exists?(added_event_id)
      refute IssueEvent.exists?(removed_event_id)
      refute IssueEvent.exists?(changed_event_id)
      # assigned event is not removed
      assert IssueEvent.exists?(assigned_event_id)
    end
  end
end
