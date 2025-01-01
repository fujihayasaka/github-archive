# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueReferencingTest < GitHub::TestCase
  fixtures do
    @repo   = create(:repository)

    Timecop.freeze(1.month.ago) do
      @issue  = create(:issue, repository: @repo, create_references: true)
      @issue2 = create(:issue, repository: @repo, create_references: true)
    end

    @user     = create(:user)
    @org      = create(:organization)
    @org_repo = create(:repository, owner: @org)

    @team = create(:team, organization: @org)
    @team.add_member @user
    @team.add_member @org.admins.first
    @team.add_repository @org_repo, :pull
  end

  test "issue referencing another issue" do
    issue = T.let(nil, T.untyped)
    Timecop.freeze(2.months.ago) do
      issue = perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) do
        create(:issue, repository: @repo, body: "check out ##{@issue.number}", create_references: true)
      end
    end
    issue.reload  # clear out usec

    ref = @issue.references.reload.detect { |r|  r.source == issue }
    refute_nil ref
    assert_equal   issue.created_at, ref.referenced_at
  end

  test "issue referencing another issue on update" do
    assert @issue.references.reload.empty?

    Timecop.freeze(1.day.ago) do
      perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) { @issue2.update(body: "check out ##{@issue.number}") }
    end
    @issue2.reload  # clear out usec

    ref = @issue.references.reload.detect { |r|  r.source == @issue2 }
    refute_nil ref
    assert_equal   @issue2.updated_at, ref.referenced_at
  end

  test "issue referencing another issue on update without body change" do
    assert @issue.references.reload.empty?

    Timecop.freeze(2.days.ago) do
      perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) { @issue2.update(body: "check out ##{@issue.number}") }
    end
    @issue2.reload  # clear out usec
    t = @issue2.updated_at

    @issue.references.reload.each(&:destroy)

    perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) { @issue2.update(title: "just testing") }

    ref = @issue.references.reload.detect { |r|  r.source == @issue2 }
    refute_nil ref
    assert_equal   t, ref.referenced_at
  end

  test "issue self-reference is ignored" do
    perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) { @issue.update(body: "check out ##{@issue.number}") }

    ref_items = @issue.references.reload.collect(&:source)
    refute_includes ref_items, @issue
  end

  test "issue comment referencing another issue" do
    comment = T.let(nil, T.untyped)
    Timecop.freeze(4.minutes.ago) do
      comment = perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) do
        create(:issue_comment, issue: @issue2, body: "check out ##{@issue.number}")
      end
      comment.reload
    end

    ref = @issue.references.reload.detect { |r|  r.source == @issue2 }
    refute_nil ref
    assert_equal comment.created_at, ref.referenced_at
  end

  test "issue comment referencing another issue on update" do
    comment = T.let(nil, T.untyped)
    Timecop.freeze(2.weeks.ago) do
      comment = perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) do
        create(:issue_comment, issue: @issue2, body: "some cool stuff")
      end
    end

    assert @issue.references.reload.empty?

    Timecop.freeze(1.day.ago) do
      perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) { comment.update(body: "check out ##{@issue.number}") }
    end
    comment.reload  # clear out usec

    ref = @issue.references.reload.detect { |r|  r.source == @issue2 }
    refute_nil ref
    assert_equal   comment.updated_at, ref.referenced_at
  end

  test "issue comment self-reference is ignored" do
    perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) { create(:issue_comment, issue: @issue, body: "check out ##{@issue.number}") }

    ref_items = @issue.references.reload.collect(&:source)
    refute_includes ref_items, @issue
  end

  test "creates references for teams" do
    assert @team.references.reload.empty?

    issue = T.let(nil, T.untyped)
    Timecop.freeze(2.hours.ago) do
      issue = create(:issue, repository: @org_repo, user: @user, create_references: true)
    end

    Timecop.freeze(1.hour.ago) do
      perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) { issue.update(body: "/cc @#{@team.organization}/#{@team.slug}") }
    end
    issue.reload  # clear out usec

    ref = @team.references.reload.detect { |r|  r.source == issue }
    refute_nil ref
    assert_equal   issue.updated_at, ref.referenced_at
  end

  test "creates references for teams on comment" do
    assert @team.references.reload.empty?

    issue = T.let(nil, T.untyped)
    Timecop.freeze(3.hours.ago) do
      issue = create(:issue, repository: @org_repo, create_references: true)
    end

    comment = T.let(nil, T.untyped)
    Timecop.freeze(2.hours.ago) do
      comment = perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) do
        issue.comments.create!(user: @user, body: "/cc @#{@team.organization}/#{@team.slug}")
      end
    end
    comment.reload  # clear out usec

    ref = @team.references.reload.detect { |r|  r.source == issue }
    refute_nil ref
    assert_equal   comment.created_at, ref.referenced_at
  end

  test "saving an issue with a deleted user and references to other things" do
    i = create(:issue, repository: @repo, create_references: true)
    @issue = perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) do
      create(:issue, repository: @repo, body: "check out ##{i.number}", create_references: true)
    end
    @issue.user.destroy
    @issue.reload

    assert @issue.close(@repo.owner)
  end
end
