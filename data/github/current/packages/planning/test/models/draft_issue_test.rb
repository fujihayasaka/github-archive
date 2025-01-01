# typed: true
# frozen_string_literal: true

require "test_helper"

class DraftIssueTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers

  fixtures do
    @admin = create(:verified_user, login: "org-admin")
    @organization = create(:organization, admin: @admin)
    @memex_project = create(:memex_project, owner: @organization)
    @memex_project_item = create(:memex_project_item, memex_project: @memex_project)
  end

  def assignee_hydro_payload(draft_issue, actor, previous_assignee = nil, current_assignees = draft_issue.assignees)
    serializer = Hydro::EntitySerializer
    {
      actor: serializer.user(actor),
      assignees: current_assignees.map { |assignee| serializer.user(assignee) },
      draft_issue: serializer.draft_issue(draft_issue),
      project_item: serializer.memex_project_item(draft_issue.memex_project_item),
      previous_assignee: previous_assignee ? serializer.user(previous_assignee) : nil,
      project: serializer.memex_project(draft_issue.memex_project_item.memex_project),
      request_context: serializer.request_context(GitHub.context.to_hash)
    }
  end

  def update_hydro_payload(draft_issue, actor, previous_title, current_title = draft_issue.title)
    serializer = Hydro::EntitySerializer
    {
      actor: serializer.user(actor),
      draft_issue: serializer.draft_issue(draft_issue),
      project_item: serializer.memex_project_item(draft_issue.memex_project_item),
      project: serializer.memex_project(draft_issue.memex_project_item.memex_project),
      title: current_title,
      previous_title: previous_title,
      request_context: serializer.request_context(GitHub.context.to_hash)
    }
  end

  context "validations" do
    test "requires a memex project item" do
      draft = build(:draft_issue)
      draft.memex_project_item = nil

      refute draft.save
      assert_includes draft.errors.full_messages, "Memex project item can't be blank"
    end

    test "disallows the empty string as a title" do
      draft = build(:draft_issue, title: "")

      refute draft.save
      assert_includes draft.errors.full_messages, "Title can't be blank"
    end

    test "disallows string with only whitespace a title" do
      draft = build(:draft_issue, title: "   ")

      refute draft.save
      assert_includes draft.errors.full_messages, "Title can't be blank"
    end

    test "disallows a title longer than the maximum allowable size" do
      draft = build(:draft_issue, title: "x" * (DraftIssue::TITLE_BYTESIZE_LIMIT + 1))

      refute draft.save
      assert_includes draft.errors.full_messages, "Title is too long (maximum is 256 characters)"
    end
  end

  context "callbacks" do
    test "destroys associated draft assignments in the background on destroy" do
      org_members = create_list(:verified_user, 3).tap { |users| users.each { |u| @organization.add_member(u) } }
      draft_issue = @memex_project.build_draft_issue(creator: org_members.first, title: "An idea").tap(&:save!).content
      draft_issue.assignees += org_members

      assert_difference(-> { DraftIssueAssignment.count }, -3) do
        perform_enqueued_jobs(only: DestroyDependentRecordsJob) do
          draft_issue.destroy!
        end
      end
    end

    test "instruments assignee create for hydro" do
      user = create(:user)
      GitHub.context.push(actor_id: user.id)
      draft_issue = create(:draft_issue)
      GlobalInstrumenter.expects(:instrument).with(
        DraftIssueAssignment::ON_CREATE_INSTRUMENTATION_KEY,
        draft_issue.hydro_assignee_payload
      )
      draft_issue.assignees = [user]
      draft_issue.save!
    end

    test "instruments assignee destroy for hydro when an assignee is directly destroyed" do
      user = create(:user)
      GitHub.context.push(actor_id: user.id)
      draft_issue = create(:draft_issue, assignees: [user])
      GlobalInstrumenter.expects(:instrument).with(
        DraftIssueAssignment::ON_DESTROY_INSTRUMENTATION_KEY,
        draft_issue.hydro_assignee_payload.merge(
          previous_assignee: user
        )
      )
      draft_issue.assignments.first.destroy!
      assert_empty draft_issue.assignments.to_a
    end

    test "instruments assignee destroy for hydro when assignees is set to an empty array" do
      user = create(:user)
      GitHub.context.push(actor_id: user.id)
      draft_issue = create(:draft_issue, assignees: [user])
      GlobalInstrumenter.expects(:instrument).with(
        DraftIssueAssignment::ON_DESTROY_INSTRUMENTATION_KEY,
        draft_issue.hydro_assignee_payload.merge(
          previous_assignee: user
        )
      )
      draft_issue.assignees = []
      draft_issue.save!
    end

    test "publishes a draft issue update assignee event to hydro when setting assignees for the first time" do
      user = create(:user)
      GitHub.context.push(actor_id: user.id)

      Timecop.freeze(Time.now) do
        reset_hydro
        draft_issue = create(:draft_issue, assignees: [user])
        expected_hydro_payload = assignee_hydro_payload(draft_issue, user)
        assert_hydro_published(expected_hydro_payload, schema: "github.memex.v0.DraftIssueUpdateAssignee", count: 1)
      end
    end

    test "publishes 2 draft issue update assignee events to hydro when changing assignees" do
      user = create(:user)
      user2 = create(:user)
      actor = user
      GitHub.context.push(actor_id: user.id)

      Timecop.freeze(Time.now) do
        draft_issue = create(:draft_issue, assignees: [user])
        reset_hydro
        draft_issue.assignees = [user2]
        draft_issue.save!
        expected_hydro_payload_create = assignee_hydro_payload(draft_issue, actor)
        expected_hydro_payload_destroy = assignee_hydro_payload(draft_issue, actor, user, [])
        assert_hydro_published(expected_hydro_payload_create, schema: "github.memex.v0.DraftIssueUpdateAssignee", count: 1)
        assert_hydro_published(expected_hydro_payload_destroy, schema: "github.memex.v0.DraftIssueUpdateAssignee", count: 1)
      end
    end

    test "publishes an issue update assignees event to hydro when unassigning" do
      user = create(:user)
      actor = user
      GitHub.context.push(actor_id: user.id)

      Timecop.freeze(Time.now) do
        draft_issue = create(:draft_issue, assignees: [user])
        reset_hydro
        draft_issue.assignees = []
        draft_issue.save!
        expected_hydro_payload_destroy = assignee_hydro_payload(draft_issue, actor, user, [])
        assert_hydro_published(expected_hydro_payload_destroy, schema: "github.memex.v0.DraftIssueUpdateAssignee", count: 1)
      end
    end

    test "instruments updates when title changes" do
      user = create(:user)
      GitHub.context.push(actor_id: user.id)
      old_title = "old title"
      new_title = "new title"
      draft_issue = create(:draft_issue, title: old_title)

      calls = {}
      GlobalInstrumenter.expects(:instrument).at_least_once.with { |key, payload| calls[key] = payload }
      draft_issue.title = new_title
      draft_issue.save!

      expected_key = DraftIssue::ON_UPDATE_INSTRUMENTATION_KEY
      expected_payload = draft_issue.hydro_update_payload.merge(title: new_title)
      assert calls[expected_key]
      assert_equal calls[expected_key], expected_payload
    end

    test "publishes hydro message when title changes" do
      user = create(:user)
      GitHub.context.push(actor_id: user.id)
      old_title = "old title"
      new_title = "new title"
      draft_issue = create(:draft_issue, title: old_title)

      draft_issue.title = new_title
      draft_issue.save!

      expected_message = update_hydro_payload(draft_issue, user, old_title)

      assert_hydro_published(
        expected_message,
        schema: "github.memex.v0.DraftIssueUpdateTitle",
        count: 1,
        ignore_extra_keys: true
      )
    end

    test "instruments updates when body changes" do
      user = create(:user)
      GitHub.context.push(actor_id: user.id)
      old_body = "old body"
      new_body = "new body"
      draft_issue = create(:draft_issue, body: old_body)

      calls = {}
      GlobalInstrumenter.expects(:instrument).at_least_once.with { |key, payload| calls[key] = payload }
      draft_issue.body = new_body
      draft_issue.save!

      expected_key = DraftIssue::ON_UPDATE_INSTRUMENTATION_KEY
      expected_payload = draft_issue.hydro_update_payload.merge(body: new_body)
      assert calls[expected_key]
      assert_equal calls[expected_key], expected_payload
    end

    test "does not publish hydro message when body changes" do
      user = create(:user)
      GitHub.context.push(actor_id: user.id)
      old_body = "old body"
      new_body = "new body"
      draft_issue = create(:draft_issue, body: old_body)
      draft_issue.body = new_body
      draft_issue.save!

      refute_hydro_messages(schema: "github.memex.v0.DraftIssueUpdateTitle")
    end

    test "does not instrument updates when title and body have not changed" do
      draft_issue = create(:draft_issue)

      expected_key = DraftIssue::ON_UPDATE_INSTRUMENTATION_KEY
      # at_least(0) enables us to be indifferent to any other invocations of :instrument, if any. If there _are_
      # any invocations, we validate that they're not related to the functionality being covered here.
      GlobalInstrumenter.expects(:instrument).at_least(0).with do |key, _|
        refute_equal expected_key, key
      end

      Timecop.travel(5.seconds) do
        draft_issue.touch
      end
    end
  end

  context "#memex_content_hash" do
    test "dumps base attributes of the object by default" do
      draft_issue = create(:draft_issue)
      expected_hash = { id: draft_issue.id }
      assert_equal expected_hash, draft_issue.memex_content_hash
    end

    test "includes the created_at date if specified" do
      time = Time.zone.now.change(usec: 0)
      draft_issue = create(:draft_issue, created_at: time)
      expected_hash = { id: draft_issue.id, created_at: time }
      assert_equal expected_hash, draft_issue.memex_content_hash(fields: [:created_at])
    end

    test "includes the updated_at date if specified" do
      time = Time.zone.now.change(usec: 0)
      draft_issue = create(:draft_issue, updated_at: time)
      expected_hash = { id: draft_issue.id, updated_at: time }
      assert_equal expected_hash, draft_issue.memex_content_hash(fields: [:updated_at])
    end

    test "includes the user hash if specified" do
      draft_issue = create(:draft_issue)
      expected_hash = { id: draft_issue.id, user: draft_issue.memex_project_item.creator.memex_column_hash }
      assert_equal expected_hash, draft_issue.memex_content_hash(fields: [:user])
    end

    test "includes the user hash if specified and the user is deleted" do
      User.create_ghost
      draft_issue = create(:draft_issue)
      draft_issue.memex_project_item.creator.destroy
      draft_issue.reload

      expected_hash = { id: draft_issue.id, user: User.ghost.memex_column_hash }
      assert_equal expected_hash, draft_issue.memex_content_hash(fields: [:user])
    end

    test "calls :html_body with the right context" do
      draft_issue = create(:draft_issue)
      context = { memex_project: draft_issue.memex_project, unfurl_references: true }

      draft_issue.expects(:public_send)
        .with(:body_html, context: context)
        .once
        .returns(nil)

      expected_hash = { id: draft_issue.id, body_html: nil }
      assert_equal expected_hash, draft_issue.memex_content_hash(fields: [:body_html])

      draft_issue.set_current_user(@admin)

      draft_issue.expects(:public_send)
        .with(:body_html, context: context.merge(current_user: @admin))
        .once
        .returns(nil)

      expected_hash = { id: draft_issue.id, body_html: nil }
      assert_equal expected_hash, draft_issue.memex_content_hash(fields: [:body_html])
    end

    test "unfurls references" do
      user = create(:user)
      repo = create(:private_repository, owner: user)
      issue = create(:issue, repository: repo, user: user, title: "supermoon")

      issue_url = "https://github.com/#{repo.nwo}/issues/#{issue.number}"
      draft_issue_body = "<ul><li>YAY #{issue_url}</li></ul>"

      draft_issue = create(:draft_issue, body: draft_issue_body)
      draft_issue.reload
      draft_issue.set_current_user(user)

      result_hash = draft_issue.memex_content_hash(fields: [:body_html])
      assert_includes result_hash[:body_html], "issue-shorthand"
    end
  end

  context "#body" do
    test "body attribute is compressed" do
      draft_issue = create(:draft_issue, body: "foo" * 100)
      draft_issue.reload
      assert draft_issue.body.bytesize > draft_issue.attributes_before_type_cast["body"].bytesize
    end
  end

  context "#body_html" do
    test "can have markdown" do
      draft_issue = create(:draft_issue, body: "**foo** bar")
      draft_issue.reload
      assert_equal "<p><strong>foo</strong> bar</p>", draft_issue.body_html
    end

    test "can have mentions" do
      user = create(:user)
      draft_issue = create(:draft_issue, body: "hello @#{user}")
      draft_issue.reload
      assert_equal(
        "<p>hello <a class=\"user-mention notranslate\" data-hovercard-type=\"user\" data-hovercard-url=\"/users/#{user}/hovercard\" data-octo-click=\"hovercard-link-click\" data-octo-dimensions=\"link_type:self\" href=\"https://github.com/#{user}\">@#{user}</a></p>",
        draft_issue.body_html
      )
    end
  end

  context "#memex_denormalized_title_value" do
    test "uses standard title HTML pipeline that formats code fences when feature flag is enabled" do
      draft_issue = @memex_project.build_draft_issue(creator: @admin, title: "Fix `code` bug")
      assert_equal "Fix <code>code</code> bug", draft_issue.memex_denormalized_title_value.dig(:title, :html)
    end
  end
end
