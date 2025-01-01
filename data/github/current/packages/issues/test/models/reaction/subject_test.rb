# typed: true
# frozen_string_literal: true

require "test_helper"

class ReactionSubjectTest < GitHub::TestCase
  setup do
    @subject = create(:issue_comment, issue_id: 1, repository_id: 1)
  end

  def create_reaction_for(subject, actor: create(:user), content: "heart")
    subject.react(actor: actor, content: content)
  end

  context "has many reactions" do
    test "works" do
      reaction = create_reaction_for(@subject)

      assert_same_elements [reaction], @subject.reactions.reload
    end

    test "doesn't modify the reactions when destroyed" do
      reaction     = create_reaction_for(@subject)
      subject_id   = reaction.subject_id
      subject_type = reaction.subject_type

      @subject.destroy

      reaction_after_destroy = IssueCommentReaction.find(reaction.id)
      assert_equal subject_id, reaction_after_destroy.subject_id
      assert_equal subject_type, reaction_after_destroy.subject_type
    end
  end

  context "grouped_reactions" do
    test "groups reactions by their content" do
      tadas   = Array.new(2) { create_reaction_for(@subject, content: "tada") }
      smiles  = Array.new(2) { create_reaction_for(@subject, content: "smile") }

      grouped_reactions = @subject.grouped_reactions

      assert_equal 2, grouped_reactions.size
      assert_same_elements tadas, grouped_reactions.detect { |g| g.first.content == "tada" }.last
      assert_same_elements smiles, grouped_reactions.detect { |g| g.first.content == "smile" }.last
    end

    test "orders groups by creation date (ascending)" do
      Timecop.freeze(24.hours.ago) do
        create_reaction_for(@subject, content: "tada")
      end

      Timecop.freeze(23.hours.ago) do
        3.times { create_reaction_for(@subject, content: "smile") }
      end

      Timecop.freeze(22.hours.ago) do
        2.times { create_reaction_for(@subject, content: "+1") }
      end

      # We use assert_equal instead of assert_same_elements here because we care
      # about the order.
      assert_equal %w(tada smile +1), @subject.grouped_reactions.map(&:first).map(&:content)
    end
  end

  context "#reaction_exists?" do
    test "returns true when a @subject has a given reaction for a user" do
      reaction = create_reaction_for(@subject)

      assert @subject.reaction_exists?(user: reaction.user, emotion: Emotion.find(:heart)), "reaction 'heart' should exist for #{reaction.user}"
    end

    test "returns false when a @subject does not have a given reaction for a user" do
      reaction = create_reaction_for(@subject)

      refute @subject.reaction_exists?(user: reaction.user, emotion: Emotion.find(:smile)), "reaction 'smile' should not exist for #{reaction.user}"
    end

    test "returns false when a @subject has no reactions for a given user" do
      create_reaction_for(@subject)

      user = create(:user)

      refute @subject.reaction_exists?(user: user, emotion: Emotion.find(:heart)), "reaction 'heart' should not exist for #{user}"
    end

    test "returns false when the user is logged out" do
      create_reaction_for(@subject)

      refute @subject.reaction_exists?(user: nil, emotion: Emotion.find(:heart))
    end
  end
end
