# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectCardRedactorTest < GitHub::TestCase

  fixtures do
    @member = create(:user)
    @owner = create(:user)
    @org = create(:organization, admin: @owner, plan: "bronze")

    @org.add_member(@member, action: :read)
    @org.update_default_repository_permission(:none, actor: @owner)

    @repo = create(:repository, owner: @org)
    @secret_repo = create(:private_repository, owner: @org)

    @project = create(:project, owner: @org)

    @note = create(:note_project_card, project: @project)
    @visible_card = create :project_card,
      project: @project,
      content: create(:issue, repository: @repo)
    @redacted_card = create :project_card,
      project: @project,
      content: create(:issue, repository: @secret_repo)
  end

  test "filters out cards the viewer can't see" do
    refute_able @member, :read, @secret_repo

    filtered_cards = ProjectCardRedactor.new(@member, @project.cards).cards

    assert_includes filtered_cards, @note
    assert_includes filtered_cards, @visible_card
    refute_includes filtered_cards, @redacted_card

    assert_equal @redacted_card.id, filtered_cards.find(&:redacted?).id
  end

  test "filters out cards with content in deleted repositories" do
    @visible_card.content.repository.destroy
    filtered_cards = ProjectCardRedactor.new(@member, @project.cards).cards
    perform_enqueued_jobs(only: [DestroyDependentRecordsJob])

    refute_includes filtered_cards, @visible_card
    assert_same_elements [@visible_card.id, @redacted_card.id], filtered_cards.find_all(&:redacted?).map(&:id)
    assert_equal ProjectCardRedactor::RedactedCard::REPOSITORY_MISSING, filtered_cards.find { |card| card.id == @visible_card.id }.reason_for_redaction
  end

  test "filters out cards that reference deleted issues" do
    DeletedIssue.delete_issue(@visible_card.content, deleter: @owner)
    perform_enqueued_jobs(only: [DestroyDependentRecordsJob])

    filtered_cards = ProjectCardRedactor.new(@member, @project.cards).cards

    refute_includes filtered_cards, @visible_card
    assert_same_elements [@redacted_card.id], filtered_cards.find_all(&:redacted?).map(&:id)
  end

  if GitHub.spamminess_check_enabled?
    test "filters out issue cards where the issue's author is spammy" do
      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) { @visible_card.content.user.mark_as_spammy }
      filtered_cards = ProjectCardRedactor.new(@member, @project.cards).cards

      refute_includes filtered_cards, @visible_card
      assert_same_elements [@visible_card.id, @redacted_card.id], filtered_cards.find_all(&:redacted?).map(&:id)
      assert_equal ProjectCardRedactor::RedactedCard::SPAMMY_CONTENT, filtered_cards.find { |card| card.id == @visible_card.id }.reason_for_redaction
    end

    test "doesn't filter out spammy issue cards authored by the viewer" do
      @visible_card.content.user.mark_as_spammy
      filtered_cards = ProjectCardRedactor.new(@visible_card.content.user, @project.cards).cards

      assert_includes filtered_cards, @visible_card
      refute_includes filtered_cards.find_all(&:redacted?).map(&:id), @visible_card.id
    end

    test "filters out note cards where the card's creator is spammy" do
      @note.creator.mark_as_spammy
      filtered_cards = ProjectCardRedactor.new(@member, @project.cards).cards

      refute_includes filtered_cards, @note
      assert_same_elements [@note.id, @redacted_card.id], filtered_cards.find_all(&:redacted?).map(&:id)
      assert_equal ProjectCardRedactor::RedactedCard::SPAMMY_CONTENT, filtered_cards.find { |card| card.id == @note.id }.reason_for_redaction
    end

    test "doesn't filter out spammy note cards authored by the viewer" do
      @note.creator.mark_as_spammy
      filtered_cards = ProjectCardRedactor.new(@note.creator, @project.cards).cards

      assert_includes filtered_cards, @note
      refute_includes filtered_cards.find_all(&:redacted?).map(&:id), @note.id
    end
  end

  test "org owners can see everything" do
    assert_able @owner, :read, @secret_repo

    filtered_cards = ProjectCardRedactor.new(@owner, @project.cards).cards

    assert_same_elements @project.cards, filtered_cards

    refute filtered_cards.any?(&:redacted?)
  end

  context "private repo-owned projects" do
    test "staff can see everything with an unlock" do
      staff = create(:staff_admin_user)
      project = create(:project, owner: @secret_repo)

      create(:project_card, project: project, content: create(:issue, repository: @secret_repo))
      create(:note_project_card, project: project)

      admin_unlock_repo(staff, @secret_repo)

      filtered_cards = ProjectCardRedactor.new(staff, project.cards).cards

      assert_same_elements project.cards, filtered_cards
      refute filtered_cards.any?(&:redacted?)
    end

    test "owner can see everything" do
      project = create(:project, owner: @secret_repo)

      create(:project_card, project: project, content: create(:issue, repository: @secret_repo))
      create(:note_project_card, project: project)

      filtered_cards = ProjectCardRedactor.new(@owner, project.cards).cards

      assert_same_elements project.cards, filtered_cards
      refute filtered_cards.any?(&:redacted?)
    end
  end
end
