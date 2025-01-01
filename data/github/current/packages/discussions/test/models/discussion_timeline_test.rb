# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionTimelineTest < GitHub::TestCase
  fixtures do
    @verified_user = create(:verified_user)

    @repo_owner = create(:user, :sponsorable)
    @public_repo = create(:repository, owner: @repo_owner, has_discussions: true)
    @category = create(:discussion_category, repository: @public_repo)
    @public_discussion = create(
      :discussion,
      :question,
      repository: @public_repo,
      category: @category,
    )

    @org = create(:business_plus_organization, :sponsorable)
    @org_repo = create(:repository, owner: @org, has_discussions: true)

    @rando_reader = create(:verified_user)

    @inactive_sponsor_reader = create(:sponsorship, :public, :inactive, sponsorable: @repo_owner).sponsor
    @sponsor_reader = create(:sponsorship, :public, sponsorable: @repo_owner).sponsor
    @private_sponsor_reader = create(:sponsorship, :private, sponsorable: @repo_owner).sponsor

    @sponsor_org_reader = create(:sponsorship, :public, sponsorable: @org).sponsor
    @private_sponsor_org_reader = create(:sponsorship, :private, sponsorable: @org).sponsor

    @repo_reader = create(:verified_user)
    @org_repo.add_member(@repo_reader, action: :read)

    @repo_triager = create(:verified_user)
    @org_repo.add_member(@repo_triager, action: :triage)

    @repo_maintainer = create(:verified_user)
    @org_repo.add_member(@repo_maintainer, action: :maintain)

    @repo_writer = create(:verified_user)
    @org_repo.add_member(@repo_writer, action: :write)

    @repo_admin = create(:verified_user)
    @org_repo.add_member(@repo_admin, action: :admin)

    @org_discussion = create(:discussion, :question, repository: @org_repo)
    @org_discussion_comment = create(:discussion_comment, discussion: @org_discussion)

    @org_repo.enable_tiered_reporting(actor: @repo_admin)

    @spammer = create(:spammy_user, :verified)

    @oldest_comment = create(:discussion_comment, discussion: @public_discussion, created_at: 3.hours.ago)
    @middle_aged_comment = create(:discussion_comment, discussion: @public_discussion,
      created_at: 90.minutes.ago)
    @answer = create(:discussion_comment, discussion: @public_discussion, created_at: 1.minute.ago)

    @answer.mark_as_answer
    @answer_event = @public_discussion.events.last

    @chronologically_sorted = [@oldest_comment, @middle_aged_comment, @answer, @answer_event]
  end

  context "#can_transfer_discussion?" do
    test "returns false when viewer lacks permission to transfer the discussion to another repository" do
      timeline = timeline_for(@public_discussion, viewer: @rando_reader)
      refute_predicate timeline, :can_transfer_discussion?
    end

    test "returns true when viewer has permission to transfer the discussion to another repository" do
      timeline = timeline_for(@public_discussion, viewer: @repo_owner)
      assert_predicate timeline, :can_transfer_discussion?
    end
  end

  context "#can_interact_with_repo?" do
    test "returns true when viewer has permission to interact with the repo" do
      timeline = timeline_for(@public_discussion, viewer: @repo_owner)
      assert_predicate timeline, :can_interact_with_repo?
    end

    test "returns false when viewer lacks permission to interact with the repo" do
      RepositoryInteractionAbility.new(@public_repo).set_ability(:collaborators_only, @repo_owner)
      timeline = timeline_for(@public_discussion, viewer: @verified_user)
      refute_predicate timeline, :can_interact_with_repo?
    end

    test "returns false for anonymous viewer" do
      timeline = timeline_for(@public_discussion, viewer: nil)
      refute_predicate timeline, :can_interact_with_repo?
    end
  end

  context "#can_reply_to_discussion_comment?" do
    test "returns false when given something other than a discussion comment" do
      timeline = timeline_for(@public_discussion, viewer: @rando_reader)
      refute timeline.can_reply_to_discussion_comment?(nil)
      refute timeline.can_reply_to_discussion_comment?(@public_discussion)
    end

    test "returns false when can't comment in general" do
      timeline = timeline_for(@public_discussion, viewer: @rando_reader)
      DiscussionTimeline.any_instance.stubs(:can_comment?).returns(false)
      refute timeline.can_reply_to_discussion_comment?(@oldest_comment)
    end

    test "returns false when the discussion is locked" do
      timeline = timeline_for(@public_discussion, viewer: @rando_reader)
      DiscussionTimeline.any_instance.stubs(:locked_discussion?).returns(true)
      refute timeline.can_reply_to_discussion_comment?(@oldest_comment)
    end

    test "returns false when the viewer is blocked from commenting" do
      timeline = timeline_for(@public_discussion, viewer: @rando_reader)
      DiscussionTimeline.any_instance.stubs(:blocked_from_commenting?).returns(true)
      refute timeline.can_reply_to_discussion_comment?(@oldest_comment)
    end

    test "returns true for a top-level comment" do
      timeline = timeline_for(@public_discussion, viewer: @rando_reader)
      assert timeline.can_reply_to_discussion_comment?(@oldest_comment)
    end

    test "returns false for a nested comment" do
      timeline = timeline_for(@public_discussion, viewer: @rando_reader)
      nested_comment = create(:discussion_comment, discussion: @public_discussion, parent_comment: @oldest_comment,
        repository: @public_repo)
      refute timeline.can_reply_to_discussion_comment?(nested_comment)
    end
  end

  context "#show_discussion_mark_answer?" do
    test "false for non-question" do
      convo = create(:discussion, repository: @org_repo)
      comment = create(:discussion_comment, discussion: convo)
      timeline = timeline_for(convo, viewer: @repo_maintainer)
      refute timeline.show_discussion_mark_answer?(comment)
    end

    test "false for anonymous viewer when comment is not marked as answer" do
      timeline = timeline_for(@org_discussion, viewer: nil)
      refute timeline.show_discussion_mark_answer?(@org_discussion_comment)
    end

    test "true for anonymous viewer when comment is marked as answer" do
      @org_discussion_comment.actor = @repo_maintainer
      assert @org_discussion_comment.mark_as_answer
      assert_predicate @org_discussion.reload, :answered?,
        "discussion should be answered for this test"
      timeline = timeline_for(@org_discussion, viewer: nil)
      assert timeline.show_discussion_mark_answer?(@org_discussion_comment)
    end

    test "false for the discussion itself" do
      timeline = timeline_for(@org_discussion, viewer: @repo_maintainer)
      refute timeline.show_discussion_mark_answer?(@org_discussion)
    end

    test "true for user who can mark the answer" do
      timeline = timeline_for(@org_discussion, viewer: @repo_maintainer)
      assert timeline.show_discussion_mark_answer?(@org_discussion_comment)
    end

    test "false for comment in discussion with category that disables answer marking" do
      DiscussionCategory.any_instance.stubs(:supports_mark_as_answer?).returns(false)
      timeline = timeline_for(@org_discussion, viewer: @repo_maintainer)
      refute timeline.show_discussion_mark_answer?(@org_discussion_comment)
    end

    test "true for comment in discussion with category that enables answer marking" do
      assert_predicate @category, :supports_mark_as_answer?
      timeline = timeline_for(@org_discussion, viewer: @repo_maintainer)
      assert timeline.show_discussion_mark_answer?(@org_discussion_comment)
    end
  end

  context "#action_or_role_level_for" do
    test "returns :write when author has write access to the repository" do
      collaborator = create(:verified_user)
      @public_repo.add_member(collaborator)
      timeline = timeline_for(@public_discussion, viewer: nil)
      comment = create(:discussion_comment, discussion: @public_discussion, user: collaborator)

      assert_equal :write, timeline.action_or_role_level_for(comment)
    end

    test "returns :triage when author has triage access to the repository" do
      timeline = timeline_for(@org_discussion, viewer: nil)
      comment = create(:discussion_comment, discussion: @org_discussion, user: @repo_triager)

      assert_equal :triage, timeline.action_or_role_level_for(comment)
    end

    test "returns :admin when author is a repo admin" do
      timeline = timeline_for(@org_discussion, viewer: nil)
      comment = create(:discussion_comment, discussion: @org_discussion, user: @repo_admin)

      assert_equal :admin, timeline.action_or_role_level_for(comment)
    end

    test "returns :maintain when author is a repo maintainer" do
      comment = create(:discussion_comment, discussion: @org_discussion, user: @repo_maintainer)
      timeline = timeline_for(@org_discussion, viewer: nil)
      assert_equal :maintain, timeline.action_or_role_level_for(comment)
    end

    test "returns :read for author with no relation to the repository who has read access" do
      rando = create(:verified_user)
      comment = create(:discussion_comment, discussion: @public_discussion, user: rando)
      timeline = timeline_for(@public_discussion, viewer: nil)
      assert_equal :read, timeline.action_or_role_level_for(comment)
    end
  end

  context ".last_modified_at_for" do
    test "returns discussion#created_at when there are no events or comments" do
      discussion = create(:discussion)

      assert_equal discussion.created_at, DiscussionTimeline.last_modified_at_for(discussion: discussion)
    end

    test "returns most recent comment's created_at if comment is last timeline item" do
      freeze_time do
        comment = create(:discussion_comment, discussion: @public_discussion)
        assert_equal comment.created_at, DiscussionTimeline.last_modified_at_for(discussion: @public_discussion)
      end
    end

    test "returns most recent event created_at if event is the last timeline item" do
      freeze_time do
        event = create(:discussion_event, discussion: @public_discussion)
        assert_equal event.created_at, DiscussionTimeline.last_modified_at_for(discussion: @public_discussion)
      end
    end
  end

  context "#last_modified_at" do
    test "returns a timestamp matching the class method" do
      timeline = timeline_for(@public_discussion, viewer: @repo_admin)

      expected_time = DiscussionTimeline.last_modified_at_for(discussion: @public_discussion)
      assert_equal expected_time, timeline.last_modified_at
    end
  end

  context "#render_mark_as_answer?" do
    test "true for comment the viewer can mark as the answer" do
      timeline = timeline_for(@org_discussion, viewer: @repo_admin)

      assert timeline.render_mark_as_answer?(@org_discussion_comment)
    end

    test "true for nested comment" do
      child_comment = create(:discussion_comment, discussion: @org_discussion,
        parent_comment: @org_discussion_comment)

      timeline = timeline_for(@org_discussion, viewer: @repo_admin)

      assert timeline.render_mark_as_answer?(child_comment)
    end

    test "true for comment when discussion is already answered" do
      timeline = timeline_for(@public_discussion, viewer: @repo_owner)
      assert_predicate @public_discussion, :answered?,
        "discussion should be answered already for this test"

      assert timeline.render_mark_as_answer?(@oldest_comment),
        "should able to render mark as answer when answer is already set"
    end

    test "false when viewer lacks ability to mark answers in the discussion" do
      timeline = timeline_for(@org_discussion, viewer: @verified_user)

      refute timeline.render_mark_as_answer?(@org_discussion_comment)
    end

    test "true when the discussion category supports marking answers" do
      @category.update!(supports_mark_as_answer: true)
      timeline = timeline_for(@public_discussion, viewer: @repo_owner)

      assert timeline.render_mark_as_answer?(@oldest_comment)
    end

    test "false when the discussion category does not support marking answers" do
      @category.update!(supports_mark_as_answer: false)
      timeline = timeline_for(@public_discussion, viewer: @repo_owner)

      refute timeline.render_mark_as_answer?(@oldest_comment)
    end
  end

  context "#show_as_answer?" do
    test "true for comment that has been marked as the answer" do
      timeline = timeline_for(@public_discussion, viewer: @verified_user)
      assert timeline.show_as_answer?(@answer)
    end

    test "false for comment that has not been marked as the answer" do
      timeline = timeline_for(@public_discussion, viewer: @verified_user)
      refute timeline.show_as_answer?(@oldest_comment)
    end

    test "false for discussion" do
      timeline = timeline_for(@public_discussion, viewer: @verified_user)
      refute timeline.show_as_answer?(@public_discussion)
    end

    test "false for comment marked as the answer in a discussion category that does not support marking answers" do
      @category.update!(supports_mark_as_answer: false)
      timeline = timeline_for(@public_discussion, viewer: @verified_user)
      refute timeline.show_as_answer?(@answer)
    end
  end

  context "#can_open_issue_from_discussion?" do
    test "true when issue repo has issues enabled" do
      timeline = timeline_for(@org_discussion, viewer: @repo_writer)

      assert_predicate timeline, :can_open_issue_from_discussion?
    end

    test "false when issue repo does not have issues enabled" do
      @org_discussion.repository.update(has_issues: false)
      timeline = timeline_for(@org_discussion, viewer: @repo_writer)

      refute_predicate timeline, :can_open_issue_from_discussion?
    end

    test "true for EMU in org owned by business", skip_enterprise: true do
      emu = create :emu
      emu_identity = emu.external_identities.first

      emu_business_org = create :enterprise_linked_organization,
      business: emu.enterprise_managed_business,
      admin: emu

      emu_business_org_repo = create :repository, owner: emu_business_org, has_discussions: true
      emu_discussion = create(:discussion, repository: emu_business_org_repo, user: emu)
      timeline = timeline_for(emu_discussion, viewer: emu)

      assert_predicate timeline, :can_open_issue_from_discussion?
    end

    test "false for EMU in user owned repo", skip_enterprise: true do
      emu = create :emu
      emu_identity = emu.external_identities.first

      emu_business_org = create :enterprise_linked_organization,
      business: emu.enterprise_managed_business,
      admin: emu

      timeline = timeline_for(@public_discussion, viewer: emu)
      refute_predicate timeline, :can_open_issue_from_discussion?
    end

    test "false for EMU in org not owned by business", skip_enterprise: true do
      emu = create :emu
      emu_identity = emu.external_identities.first

      emu_business_org = create :enterprise_linked_organization,
      business: emu.enterprise_managed_business,
      admin: emu

      timeline = timeline_for(@org_discussion, viewer: emu)
      refute_predicate timeline, :can_open_issue_from_discussion?
    end
  end

  context "#can_report?" do
    test "returns false for rando reader" do
      timeline = timeline_for(@org_discussion, viewer: @rando_reader)
      refute timeline.can_report?(@org_discussion)
    end

    test "returns true for repo reader" do
      timeline = timeline_for(@org_discussion, viewer: @repo_reader)
      assert timeline.can_report?(@org_discussion)
    end

    test "returns true for repo triager" do
      timeline = timeline_for(@org_discussion, viewer: @repo_triager)
      assert timeline.can_report?(@org_discussion)
    end

    test "returns true for repo maintainer" do
      timeline = timeline_for(@org_discussion, viewer: @repo_maintainer)
      assert timeline.can_report?(@org_discussion)
    end

    test "returns true for repo writer" do
      timeline = timeline_for(@org_discussion, viewer: @repo_writer)
      assert timeline.can_report?(@org_discussion)
    end

    test "returns true for repo admin" do
      timeline = timeline_for(@org_discussion, viewer: @repo_admin)
      assert timeline.can_report?(@org_discussion)
    end

    test "returns false for repo writer in private repo" do
      Repository.where(id: @org_repo.id).update_all(public: false)
      timeline = timeline_for(@org_discussion, viewer: @repo_writer)
      refute timeline.can_report?(@org_discussion)
    end

    test "returns false for repo admin in private repo" do
      Repository.where(id: @org_repo.id).update_all(public: false)
      timeline = timeline_for(@org_discussion, viewer: @repo_admin)
      refute timeline.can_report?(@org_discussion)
    end
  end if GitHub.can_report?

  context "#can_react?" do
    test "returns true for rando user on a discussion" do
      timeline = timeline_for(@org_discussion, viewer: @rando_reader)
      assert timeline.can_react?(@org_discussion)
    end

    test "returns true for rando user on a comment" do
      timeline = timeline_for(@org_discussion, viewer: @rando_reader)
      assert timeline.can_react?(@org_discussion_comment)
    end

    test "returns false for a blocked user on a discussion" do
      @org_discussion.author.block(@rando_reader)
      timeline = timeline_for(@org_discussion, viewer: @rando_reader)
      refute timeline.can_react?(@org_discussion)
    end

    test "returns false for a blocked user on a comment" do
      @org_discussion_comment.author.block(@rando_reader)
      timeline = timeline_for(@org_discussion, viewer: @rando_reader)
      refute timeline.can_react?(@org_discussion_comment)
    end

    test "returns false for discussions when repository is archived" do
      @org_repo.set_archived
      timeline = timeline_for(@org_discussion, viewer: @rando_reader)
      refute timeline.can_react?(@org_discussion)
    end

    test "returns false for comments when repository is archived" do
      @org_repo.set_archived
      timeline = timeline_for(@org_discussion, viewer: @rando_reader)
      refute timeline.can_react?(@org_discussion_comment)
    end
  end

  context "#can_report_to_maintainer?" do
    test "returns false for rando reader" do
      timeline = timeline_for(@org_discussion, viewer: @rando_reader)
      refute timeline.can_report_to_maintainer?(@org_discussion)
    end

    test "returns true for repo reader" do
      timeline = timeline_for(@org_discussion, viewer: @repo_reader)
      assert timeline.can_report_to_maintainer?(@org_discussion)
    end

    test "returns false for repo admin" do
      timeline = timeline_for(@org_discussion, viewer: @repo_admin)
      refute timeline.can_report_to_maintainer?(@org_discussion)
    end
  end if GitHub.can_report?

  context "#can_close_discussion?" do
    test "true for user who can close discussion" do
      timeline = timeline_for(@org_discussion, viewer: @repo_admin)
      assert_predicate timeline, :can_close_discussion?
    end

    test "false for unauthorized user" do
      timeline = timeline_for(@org_discussion, viewer: @rando_reader)
      refute_predicate timeline, :can_close_discussion?
    end
  end

  context "#can_reopen_discussion?" do
    test "true for user who can close discussion" do
      timeline = timeline_for(@org_discussion, viewer: @repo_admin)
      assert_predicate timeline, :can_reopen_discussion?
    end

    test "false for unauthorized user" do
      timeline = timeline_for(@org_discussion, viewer: @rando_reader)
      refute_predicate timeline, :can_reopen_discussion?
    end
  end

  context "#reaction_groups" do
    test "returns the same number of reaction groups as the number of available emotions" do
      timeline = timeline_for(@org_discussion, viewer: @rando_reader)
      assert Emotion.all.count, timeline.reaction_groups(@org_discussion).count
    end

    test "returns empty array on a discussion without reactions" do
      timeline = timeline_for(@org_discussion, viewer: @rando_reader)
      assert get_reactions_from_groups(timeline.reaction_groups(@org_discussion)).empty?
    end

    test "returns empty array on a comment without reactions" do
      timeline = timeline_for(@org_discussion, viewer: @rando_reader)
      assert get_reactions_from_groups(timeline.reaction_groups(@org_discussion_comment)).empty?
    end

    test "returns the list of reactions of a discussion" do
      @org_discussion.react(actor: @repo_reader, content: "+1")

      timeline = timeline_for(@org_discussion, viewer: @rando_reader)

      assert_equal [[@repo_reader.id]], get_reactions_from_groups(timeline.reaction_groups(@org_discussion))
    end

    test "returns the list of reactions of a discussion comment" do
      @org_discussion_comment.react(actor: @repo_reader, content: "+1")

      timeline = timeline_for(@org_discussion, viewer: @rando_reader)

      assert_equal [[@repo_reader.id]], get_reactions_from_groups(timeline.reaction_groups(@org_discussion_comment))
    end
  end

  context "#child_comments" do
    test "returns child comments for the provided top-level comment" do
      child_comment = create(:discussion_comment, discussion: @public_discussion, parent_comment: @oldest_comment)
      timeline = timeline_for(@public_discussion, viewer: @repo_owner)
      assert_equal [child_comment], timeline.child_comments(@oldest_comment)
    end

    test "returns empty array if top-level comment has no child comments" do
      top_level_comment = create(:discussion_comment, discussion: @public_discussion)
      timeline = timeline_for(@public_discussion, viewer: @repo_owner)
      assert_empty timeline.child_comments(top_level_comment)
    end

    test "doesn't return top-level comments if you pass a comment with a nil id" do
      comment_with_nil_id = build :discussion_comment
      timeline = timeline_for(@public_discussion, viewer: @repo_owner)
      assert_empty timeline.child_comments(comment_with_nil_id)
    end

    test "only makes 1 query for child comments across multiple parent comments" do
      timeline = timeline_for(@public_discussion, viewer: @repo_owner)

      # Make sure we have multiple top-level comments, otherwise this test is invalid
      assert_operator @public_discussion.comments.top_level.count, :>, 1

      # This will "prime" the render context object so the render context doesn't
      # add to the query count assertion below
      timeline.all_timeline_items

      assert_max_query_count_per_table({ discussion_comments: 1 }) do
        timeline.child_comments(@oldest_comment)
        timeline.child_comments(@middle_aged_comment)
      end
    end
  end

  context "#vote_for" do
    test "finds the vote for a comment" do
      vote = create(:discussion_comment_vote, comment: @answer, user: @repo_owner)

      timeline = timeline_for(@public_discussion, viewer: @repo_owner)

      assert_equal vote, timeline.vote_for(@answer)
    end

    test "finds the vote for a discussion" do
      vote = create(:discussion_vote, discussion: @public_discussion, user: @repo_owner)

      timeline = timeline_for(@public_discussion, viewer: @repo_owner)

      assert_equal vote, timeline.vote_for(@public_discussion)
    end

    test "return nil if no vote exists" do
      timeline = timeline_for(@public_discussion, viewer: @repo_owner)

      refute timeline.vote_for(@public_discussion)
    end
  end

  def get_reactions_from_groups(reaction_groups)
    reaction_groups.select { |group| group.user_ids.count > 0 }.map { |group| group.user_ids }
  end

  sig { params(discussion: Discussion, attrs: T.untyped).returns(DiscussionTimeline) }
  def timeline_for(discussion, **attrs)
    render_context = DiscussionTimeline::PaginatedRenderContext.new(
      discussion,
      **T.unsafe(**attrs),
    )

    DiscussionTimeline.new(render_context: render_context)
  end

  context "#total_visible_child_comments_count" do
    test "returns total child comments count for the provided top-level comment" do
      create(:discussion_comment, discussion: @public_discussion, parent_comment: @oldest_comment)
      timeline = timeline_for(@public_discussion, viewer: @repo_owner)

      assert_equal 1, timeline.total_visible_child_comments_count(@oldest_comment)
    end

    test "returns total child comments count ignoring pagination for the provided top-level comment" do
      create_list(:discussion_comment, 5, discussion: @public_discussion, parent_comment: @oldest_comment)
      timeline = timeline_for(@public_discussion, viewer: @repo_owner)
      timeline.stubs(:max_number_of_nested_comments_to_render).returns(1)

      assert_equal 5, timeline.total_visible_child_comments_count(@oldest_comment)
    end

    test "returns total child comments ignoring spammy comments", skip_enterprise: true do
      spammy_user = create(:user, :verified, spammy: true)
      create(:discussion_comment, discussion: @public_discussion, parent_comment: @oldest_comment, user: spammy_user)
      create(:discussion_comment, discussion: @public_discussion, parent_comment: @oldest_comment)
      timeline = timeline_for(@public_discussion, viewer: @repo_owner)

      assert_equal 1, timeline.total_visible_child_comments_count(@oldest_comment)
    end

    test "returns 0 if top-level comment has no child comments" do
      timeline = timeline_for(@public_discussion, viewer: @repo_owner)

      assert_equal 0, timeline.total_visible_child_comments_count(@oldest_comment)
    end
  end

  context ".preload_for_display" do
    test "efficiently preloads relations used when rendering discussions/comments and icons in views" do
      records = [
        create(:discussion, repository: @public_repo),
        create(:discussion, repository: @public_repo, user: create(:bot)),
        create(:discussion, repository: @public_repo, performed_via_integration: create(:integration)),
        create(:discussion_comment, repository: @public_repo),
        create(:discussion_comment, repository: @public_repo, user: create(:bot)),
        create(:discussion_comment, repository: @public_repo, user: create(:bot)),
        create(:discussion_comment, repository: @public_repo, performed_via_integration: create(:integration)),
        create(:discussion_comment, repository: @public_repo, performed_via_integration: create(:integration)),
      ]

      # Unload relations
      records.each(&:reload)

      assert_query_count_per_table({ users: 2, integrations: 2, primary_avatars: 1 }) do
        DiscussionTimeline.preload_for_display(records)
      end

      assert_query_count(0) do
        records.each do |record|
          record.performed_via_integration&.preferred_avatar_url(size: 40)
          record.user.primary_avatar_url(30)
        end
      end
    end

    test "preloads correctly when deleted users are present" do
      comment = create(:discussion_comment, repository: @public_repo)
      comment.update!(user: nil)

      assert_query_count_per_table({ users: 0, integrations: 0, primary_avatars: 0 }) do
        DiscussionTimeline.preload_for_display([comment])
      end
    end
  end

  context "#author_is_sponsor?" do
    if GitHub.sponsors_enabled?
      context "Individual sponsoring Individual" do
        test "returns true when the viewer is sponsoring repo owner" do
          comment = create(:discussion_comment, discussion: @public_discussion, user: @sponsor_reader)
          timeline = timeline_for(@public_discussion, viewer: @sponsor_reader)

          assert timeline.author_is_sponsor?(comment.user_id)
        end

        test "returns true when the viewer is a random user and the comment was created by a public sponsor" do
          comment = create(:discussion_comment, discussion: @public_discussion, user: @sponsor_reader)
          timeline = timeline_for(@public_discussion, viewer: @rando_reader)

          assert timeline.author_is_sponsor?(comment.user_id)
        end

        test "returns true when the viewer is the maintainer and the comment was created by a private sponsor" do
          comment = create(:discussion_comment, discussion: @public_discussion, user: @private_sponsor_reader)
          timeline = timeline_for(@public_discussion, viewer: @repo_owner)

          assert timeline.author_is_sponsor?(comment.user_id)
        end

        test "returns false when the viewer is a random user and the comment was created by a private sponsor" do
          comment = create(:discussion_comment, discussion: @public_discussion, user: @private_sponsor_reader)
          timeline = timeline_for(@public_discussion, viewer: @rando_reader)

          refute timeline.author_is_sponsor?(comment.user_id)
        end
      end

      context "Individual sponsoring Org" do
        test "returns true when the viewer is sponsoring the organization" do
          comment = create(:discussion_comment, discussion: @org_discussion, user: @sponsor_org_reader)
          timeline = timeline_for(@org_discussion, viewer: @sponsor_org_reader)

          assert timeline.author_is_sponsor?(comment.user_id)
        end

        test "returns true when the viewer is a random user and the comment was created by a public sponsor" do
          comment = create(:discussion_comment, discussion: @org_discussion, user: @sponsor_org_reader)
          timeline = timeline_for(@org_discussion, viewer: @rando_reader)

          assert timeline.author_is_sponsor?(comment.user_id)
        end

        test "returns true when the viewer is the maintainer and the comment was created by a private sponsor" do
          comment = create(:discussion_comment, discussion: @org_discussion, user: @private_sponsor_org_reader)
          timeline = timeline_for(@org_discussion, viewer: @org)

          assert timeline.author_is_sponsor?(comment.user_id)
        end

        test "returns false when the viewer is a random user and the comment was created by a private sponsor" do
          comment = create(:discussion_comment, discussion: @org_discussion, user: @private_sponsor_reader)
          timeline = timeline_for(@org_discussion, viewer: @rando_reader)

          refute timeline.author_is_sponsor?(comment.user_id)
        end
      end

      context "Inactive sponsorship" do
        test "return false when the viewer has only an inactive sponsorship of the repo owner" do
          comment = create(:discussion_comment, discussion: @public_discussion, user: @inactive_sponsor_reader)
          timeline = timeline_for(@public_discussion, viewer: @inactive_sponsor_reader)

          refute timeline.author_is_sponsor?(comment.user_id)
        end

        test "return false when the viewer is a random user and the author has only an inactive sponsorship of the repo owner" do
          comment = create(:discussion_comment, discussion: @public_discussion, user: @inactive_sponsor_reader)
          timeline = timeline_for(@public_discussion, viewer: @rando_reader)

          refute timeline.author_is_sponsor?(comment.user_id)
        end

        test "return false when the viewer is the maintainer and the author has only an inactive sponsorship of the repo owner" do
          comment = create(:discussion_comment, discussion: @public_discussion, user: @inactive_sponsor_reader)
          timeline = timeline_for(@public_discussion, viewer: @repo_owner)

          refute timeline.author_is_sponsor?(comment.user_id)
        end
      end

      test "return false when the viewer has never been a sponsor of the repo owner" do
        comment = create(:discussion_comment, discussion: @public_discussion, user: @repo_reader)
        timeline = timeline_for(@public_discussion, viewer: @repo_reader)

        refute timeline.author_is_sponsor?(comment.user_id)
      end
    else
      test "returns false when Sponsors is disabled" do
        comment = create(:discussion_comment, discussion: @public_discussion, user: @sponsor_reader)
        timeline = timeline_for(@public_discussion, viewer: @sponsor_reader)

        refute timeline.author_is_sponsor?(comment.user_id)
      end
    end
  end

  context "#can_manage_category_pins?" do
    test "true when the user can manage spotlights" do
      User.any_instance.stubs(:can_manage_discussion_spotlights?).returns(true)

      timeline = timeline_for(@public_discussion, viewer: @repo_owner)
      assert timeline.can_manage_category_pins?
    end

    test "false when the user cannot manage spotlights" do
      User.any_instance.stubs(:can_manage_discussion_spotlights?).returns(false)

      timeline = timeline_for(@public_discussion, viewer: @repo_owner)
      refute timeline.can_manage_category_pins?
    end
  end

  context "#selected_answer" do
    test "returns selected answer for discussion" do
      assert_predicate @public_discussion, :answered?
      timeline = timeline_for(@public_discussion, viewer: @verified_user)
      assert_equal @answer, timeline.selected_answer
    end

    test "reutrns nil if discussion is not answered" do
      @answer.unmark_as_answer
      refute_predicate @public_discussion.reload, :answered?
      timeline = timeline_for(@public_discussion, viewer: @verified_user)
      assert_nil timeline.selected_answer
    end
  end
end
