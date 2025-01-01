# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueAssignmentTest < GitHub::TestCase
  include HydroTestHelpers


  fixtures do
    @owner        = create :user, login: "owner", plan: "large"
    @collaborator = create :user, login: "collaborator"
    @unauthed     = create :user, login: "unauthed"
    @repo         = create :private_repository, owner: @owner
    @issue        = create :issue, repository: @repo, user: @repo.owner

    @collab_repo  = create :repository, owner: @owner
    @collab_1     = create :user, login: "collab-1"
    @collab_2     = create :user, login: "collab-2"
    @collab_3     = create :user, login: "collab-3"

    @repo.add_member @collaborator

    @collab_repo.add_member @collab_1
    @collab_repo.add_member @collab_2
    @collab_repo.add_member @collab_3
  end

  context("IssueAssignment") do
    context "#assigned_to?" do
      test "returns false if passed nil" do
        refute @issue.assigned_to?(nil)
      end
    end

    context "#assignee=" do
      test "replaces existing assignments when multiple assignees is enabled" do
        assert_difference("@issue.assignees.reload.count", 1) do
          @issue.assignee = @collaborator
        end
        assert_no_difference("@issue.assignees.reload.count") do
          @issue.assignee = @owner
        end
      end

      test "clears all assignees when assignee is nil and multi-assignees disabled" do
        assert_difference("@issue.assignees.reload.count", 1) do
          @issue.assignee = @collaborator
          @issue.save!
        end
        assert_difference("@issue.assignees.reload.count", -1) do
          @issue.assignee = nil
          @issue.save!
        end
      end

      test "works when former assignee is deleted" do
        @issue.assignee = @collaborator
        @issue.save!
        @collaborator.destroy
        @issue.reload
        assert_empty @issue.assignees

        @issue.assignee = @owner
        @issue.save!
        @issue.reload
        assert_equal @owner, @issue.assignee
        assert_equal [@owner], @issue.assignees.reload
      end
    end

    context "#assignees=" do
      test "sets assignees" do
        assert_empty @issue.assignees
        @issue.assignees = [@owner]
        @issue.save!
        assert_equal [@owner], @issue.assignees.reload
      end

      test "sets assignee (for backwards compatibility)" do
        assert_empty @issue.assignees
        @issue.assignees = [@owner]
        @issue.save!
        assert_equal @owner, @issue.assignee
      end

      test "clears assignee and assignees (when empty)" do
        assert_empty @issue.assignees
        @issue.assignees = [@owner]
        @issue.save!
        refute_empty @issue.assignees.reload
        @issue.assignees = []
        @issue.save!
        assert_empty @issue.assignees.reload
        assert_nil @issue.assignee
      end

      test "sets the first assignee as assignee when there are multiple" do
        @issue.assignees = [@collaborator, @owner]
        @issue.save!
        assert_equal @collaborator, @issue.assignee

        # Clear all assignments on @issue
        @issue.assignees = []

        # Double check by setting in reverse order
        @issue.assignees = [@owner, @collaborator]
        @issue.save!
        assert_equal @owner, @issue.assignee
      end

      test "does not attempt to return deleted users" do
        @issue.assignees = [@collaborator]
        @issue.save!
        @collaborator.destroy
        @issue.reload
        assert_empty @issue.assignments
        assert_empty @issue.assignees.reload
        assert_nil @issue.assignee_id
      end

      test "does not allow blocking users to be assigned by ignored user" do
        @collaborator.block @owner
        @issue.assignees = [@collaborator]

        # need to set this so modifying_user is set correctly
        GitHub.context.push(actor_id: @issue.user.id)

        assert_equal "unable to be set", @issue.errors[:assignees].first

        @issue.save

        @issue.reload
        assert_empty @issue.assignments
        assert_empty @issue.assignees.reload
        assert_nil @issue.assignee_id
      end

      test "sets assignees with mannequin user" do
        repo = create :repository
        issue = create(:issue, repository: repo)

        mannequin = create(:mannequin)
        user = create(:user)

        create(:issue_comment, issue: issue, user: mannequin)
        create(:issue_comment, issue: issue, user: user)

        assert_empty issue.assignees

        issue.assignees = [mannequin, user]
        issue.save!

        assert_same_elements [mannequin, user], issue.assignees.reload
      end
    end

    context "add_assignees" do
      test "adds the specified assignees to the issue" do
        other_collaborator = create(:user, login: "other-collaborator")
        @repo.add_member(other_collaborator)
        @issue.assignees = [@owner]
        @issue.save!

        returned = @issue.add_assignees(@collaborator, other_collaborator, @owner)
        @issue.save

        assert_same_elements [@collaborator, other_collaborator, @owner], @issue.assignees.reload
        assert_equal @issue, returned
      end

      test "truncates at 10 assignees" do
        too_many_assignees = 11.times.map do
          create(:user).tap do |user|
            @repo.add_member(user)
          end
        end

        @issue.assignees = too_many_assignees
        assert_predicate @issue, :valid?
        assert_equal Issue::AssignmentDependency::DEFAULT_ASSIGNEE_LIMIT, @issue.assignees.size
      end

      test "truncates at 1 assignee for free orgs in Munich feature flag" do
        org = create :organization, admin: @owner, plan: "free"
        repo = create :private_repository, owner: org
        issue = create :issue, repository: repo, user: @owner

        too_many_assignees = 2.times.map do
          create(:user).tap do |user|
            repo.add_member(user)
          end
        end

        issue.assignees = too_many_assignees
        assert_predicate issue, :valid?
        assert_equal 1, issue.assignees.size
      end

      test "limited to one assignee on free org plans" do
        org = create :organization, admin: @owner, plan: "free"
        repo = create :private_repository, owner: org
        issue = create :issue, repository: repo, user: @owner
        user = create :user
        repo.add_member user

        issue.assignees = [@owner]
        assert issue.assigned_to? @owner

        # even when providing the user and the owner, the previous assignee should be removed
        issue.assignees = [@owner, user]

        assert_equal 1, issue.assignees.size
        assert issue.assigned_to? user
      end

      test "limited to one assignee on disabled org plans" do
        org = create :organization, admin: @owner, plan: "business"
        repo = create :private_repository, owner: org
        issue = create :issue, repository: repo, user: @owner
        user = create :user
        repo.add_member user

        org.disable!

        issue.assignees = [@owner, user]
        assert_equal 1, issue.assignees.size
      end
    end

    context "remove_assignees" do
      test "removes the specified assignees from the issue" do
        other_collaborator = create(:user, login: "other-collaborator")
        @repo.add_member(other_collaborator)

        @issue.assignees = [@collaborator, other_collaborator, @owner]
        @issue.save
        @issue.reload

        @issue.remove_assignees(other_collaborator, @owner)
        @issue.save

        assert_same_elements [@collaborator], @issue.assignees.reload
      end

      test "returns the assignees that were successfully removed" do
        @issue.assignees = [@collaborator, @owner]
        @issue.save

        result = @issue.remove_assignees(@owner, create(:user, login: "not-really-an-assignee"))

        assert_equal @issue, result
      end

      test "destroys the associated assignment" do
        @issue.assignee = @collaborator
        @issue.save

        assignment = @issue.assignments.for_assignee(@collaborator).first

        @issue.remove_assignees(@collaborator)
        @issue.save!

        assert_nil Assignment.find_by(id: assignment.id)
      end

      test "re-syncs the issue's assignee_id if there's another assignee" do
        other_collaborator = create(:user, login: "other-collaborator")
        @repo.add_member(other_collaborator)

        @issue.assignees = [@collaborator, other_collaborator, @owner]
        @issue.save
        @issue.reload

        assert_equal @collaborator.id, @issue.assignee_id

        @issue.remove_assignees(@collaborator, @owner)
        @issue.save
        @issue.reload

        assert_equal other_collaborator.id, @issue.assignee_id
      end

      test "clears the issue's assignee_id if there are no other assignees" do
        @issue.assignees = [@collaborator, @owner]
        @issue.save
        @issue.reload

        assert_equal @collaborator.id, @issue.assignee_id

        @issue.remove_assignees(@collaborator, @owner)
        @issue.save
        @issue.reload

        assert_nil @issue.assignee_id
      end
    end

    context "available_assignee_ids" do
      test "returns the owner, collaborators, and issue author for an issue on a user-owned repo" do
        repo_owner   = create(:user, login: "repo-owner")
        repo         = create(:repository, owner: repo_owner)
        author       = create(:user, login: "author")
        issue        = create(:issue, repository: repo, user: author)
        collaborator = create(:user, login: "repo-collaborator")
        commenter    = create(:user)
        issue_comment = create(:issue_comment, issue: issue, user: commenter)
        repo.add_member(collaborator)

        assert_same_elements [repo_owner.id, collaborator.id, author.id, issue_comment.user.id], issue.available_assignee_ids
      end

      test "limits the returned list when limit is passed" do
        repo_owner   = create(:user, login: "repo-owner")
        repo         = create(:repository, owner: repo_owner)
        author       = create(:user, login: "author")
        issue        = create(:issue, repository: repo, user: author)
        collaborator = create(:user, login: "repo-collaborator")
        repo.add_member(collaborator)

        # should prioritise returning commenters
        issue_comment = create(:issue_comment, issue: issue)

        available_assignee_ids = issue.available_assignee_ids(limit: 2)
        assert_equal 2, available_assignee_ids.size
        assert_includes available_assignee_ids, issue_comment.user.id
      end

      test "returns the assignee suggestions according to the viewer's permissions" do
        owner = create(:user)
        org = create(:organization, admin: owner)
        org.update_default_repository_permission(:read, actor: owner)
        public_org_member = create(:user)
        org.add_member(public_org_member)
        org.publicize_member(public_org_member)

        public_repo = create(:repository, owner: org)
        author = create(:user, login: "author")
        issue = create(:issue, repository: public_repo, user: author)
        commenter = create(:user)
        issue_comment = create(:issue_comment, issue: issue, user: commenter)
        collaborator = create(:user, login: "repo-collaborator")
        public_repo.add_member(collaborator)

        # For the collaborator, all users should be visible
        assert_same_elements [owner.id, public_org_member.id, collaborator.id, author.id, issue_comment.user.id], issue.visible_available_assignee_ids_for(collaborator)

        # For a public user, only the public org member and the commenter should be visible
        # See this comment for why a commenter is visible - https://github.com/github/github/pull/259264/files?show-viewed-files=true&file-filters%5B%5D=#r1107322978
        viewer = create(:user)
        assert_same_elements [public_org_member.id, issue_comment.user.id], issue.visible_available_assignee_ids_for(viewer)
      end
    end

    context "sorted_assignees_list" do
      test "includes current user at the top" do
        # need to set this so modifying_user is set correctly
        GitHub.context.push(actor_id: @collab_1.id)

        issue = create :issue, repository: @collab_repo, user: @collab_repo.owner

        assert_equal [@collab_1, @collab_2, @collab_3, @owner], issue.sorted_assignees_list(current_user: @collab_1)
      end

      test "includes assigned user at the top (when logged out)" do
        issue = create :issue, repository: @collab_repo, user: @collab_repo.owner
        issue.assignee = @collab_3
        issue.save!

        assert_equal [@collab_3, @collab_1, @collab_2, @owner], issue.sorted_assignees_list(current_user: nil)
      end

      test "includes current user then assigned user at the top (when logged in)" do
        # need to set this so modifying_user is set correctly
        GitHub.context.push(actor_id: @owner.id)

        issue = create :issue, repository: @collab_repo, user: @collab_repo.owner
        issue.assignee = @collab_2
        issue.save!

        assert_equal [@owner, @collab_2, @collab_1, @collab_3], issue.sorted_assignees_list(current_user: @owner)
      end

      test "includes assignees first (after current user)" do
        # need to set this so modifying_user is set correctly
        GitHub.context.push(actor_id: @owner.id)

        issue = create :issue, repository: @collab_repo, user: @collab_repo.owner
        issue.assignees = [@collab_2, @collab_3]
        issue.save!

        assert_equal [@owner, @collab_2, @collab_3, @collab_1], issue.sorted_assignees_list(current_user: @owner)
      end

      test "includes uniq set of users for an initialized issue" do
        # need to set this so modifying_user is set correctly
        GitHub.context.push(actor_id: @owner.id)

        issue = build :issue, repository: @collab_repo, user: @collab_1
        issue.assignee = @collab_1
        issue.save!

        assert_equal [@owner, @collab_1, @collab_2, @collab_3], issue.sorted_assignees_list(current_user: @owner)
      end

      test "subsequent calls returns a different order for different current users" do
        issue = create :issue, repository: @collab_repo, user: @collab_repo.owner

        suggestions_for_owner = issue.sorted_assignees_list(current_user: @owner)
        suggestions_for_collaborator = issue.sorted_assignees_list(current_user: @collab_1)

        refute_equal suggestions_for_owner, suggestions_for_collaborator
        assert_equal @owner, suggestions_for_owner.first
        assert_equal @collab_1, suggestions_for_collaborator.first
      end

      test "Correctly filters for assigneess with profile name" do
        # need to set this so modifying_user is set correctly
        GitHub.context.push(actor_id: @owner.id)

        @collab_1.update(profile_name: "cool name")
        @owner.update(profile_name: "mega name")

        issue = build :issue, repository: @collab_repo, user: @collab_1
        issue.assignee = @collab_1
        issue.save!

        assert_equal [@collab_1], issue.filtered_assignees_list(@owner, "cool")
        assert_equal [@owner], issue.filtered_assignees_list(@owner, "mega")
        assert_equal [@collab_1, @owner], issue.filtered_assignees_list(@owner, "name")
      end

      test "Correctly filters for assigneess with login" do
        # need to set this so modifying_user is set correctly
        GitHub.context.push(actor_id: @owner.id)

        issue = build :issue, repository: @collab_repo, user: @collab_1
        issue.assignee = @collab_1
        issue.save!

        assert_equal [@collab_1], issue.filtered_assignees_list(@owner, "lab-1")
        assert_equal [@collab_2], issue.filtered_assignees_list(@owner, "lab-2")
        assert_equal [@collab_1], issue.filtered_assignees_list(@owner, "1")
        assert_equal [@owner], issue.filtered_assignees_list(@owner, "owner")
      end

      test "Correctly filters for assigneess with login and name" do
        # need to set this so modifying_user is set correctly
        GitHub.context.push(actor_id: @owner.id)

        @collab_1.update(profile_name: "own name")
        @owner.update(profile_name: "mega")

        issue = build :issue, repository: @collab_repo, user: @collab_1
        issue.assignee = @collab_1
        issue.save!

        assert_equal [@collab_1], issue.filtered_assignees_list(@owner, "collab-1")
        assert_equal [@collab_1], issue.filtered_assignees_list(@owner, "ab-1")

        assert_equal [@owner, @collab_1], issue.filtered_assignees_list(@owner, "own")
        assert_equal [@collab_1, @owner], issue.filtered_assignees_list(@owner, "wn")
      end

      test "Select created_at for users so that we can generate GraphQL global ids if needed" do
        # need to set this so modifying_user is set correctly
        GitHub.context.push(actor_id: @owner.id)

        @collab_1.update(profile_name: "cool name")
        issue = build :issue, repository: @collab_repo, user: @collab_1

        results = issue.filtered_assignees_list(@owner, "cool")
        assert_equal [@collab_1], results
        assert results.all? { |u| u.created_at.present? }
      end

      # https://github.com/github/github/blob/master/app/models/bot.rb#L250-L252
      test "does not include bots as an assignee" do
        # need to set this so modifying_user is set correctly
        GitHub.context.push(actor_id: @owner.id)

        installation = make_integration_installation(integration: @integration, repository: @collab_repo)
        bot = installation.integration.bot

        issue = build :issue, repository: @collab_repo, user: bot

        refute_includes issue.sorted_assignees_list(current_user: @owner), bot
      end

      # see: https://github.com/github/issues/issues/9264
      # fetching the business_id is required when this api is called from GraphQL because of EMU/Proxima specific checks
      test "sorted_assignees_list is fetching business id" do
        # need to set this so modifying_user is set correctly
        GitHub.context.push(actor_id: @collab_1.id)

        issue = create :issue, repository: @collab_repo, user: @collab_repo.owner

        results = issue.sorted_assignees_list(current_user: @collab_1)
        assert_equal [@collab_1, @collab_2, @collab_3, @owner], results
        assert results.all? { |u| u.business_id.present? }
      end

      # see: https://github.com/github/issues/issues/9264
      # fetching the business_id is required when this api is called from GraphQL because of EMU/Proxima specific checks
      test "filtered_assignees_list is fetching business id" do
        # need to set this so modifying_user is set correctly
        GitHub.context.push(actor_id: @owner.id)

        @collab_1.update(profile_name: "cool name")
        @owner.update(profile_name: "mega name")

        issue = build :issue, repository: @collab_repo, user: @collab_1

        results = issue.filtered_assignees_list(@owner, "name")
        assert_equal [@collab_1, @owner], results
        assert results.all? { |u| u.business_id.present? }
      end
    end

    context "#suspended_and_blocking_user_ids" do
      test "returns suspended user ids" do
        repo_owner   = create(:user, login: "repo-owner")
        repo         = create(:repository, owner: repo_owner)
        author       = create(:user, login: "author")
        issue        = create(:issue, repository: repo, user: author)
        collaborator = create(:user, login: "repo-collaborator")
        repo.add_member(collaborator)
        collaborator.suspend("reasons")

        assert_same_elements [collaborator.id], issue.suspended_and_blocking_user_ids([repo_owner.id, author.id, collaborator.id])
      end

      test "returns blocking user ids" do
        repo_owner   = create(:user, login: "repo-owner")
        repo         = create(:repository, owner: repo_owner)
        author       = create(:user, login: "author")
        issue        = create(:issue, repository: repo, user: author)
        collaborator = create(:user, login: "repo-collaborator")
        repo.add_member(collaborator)

        # need to set this so modifying_user is set correctly
        GitHub.context.push(actor_id: author.id)

        collaborator.block(author)
        assert_same_elements [collaborator.id], issue.suspended_and_blocking_user_ids([repo_owner.id, author.id, collaborator.id])
      end
    end

    context "assignee events" do
      test "generates an event for setting multiple assignees" do
        @issue.assignees = [@owner, @collaborator]
        @issue.save

        assert_equal "assigned", @issue.events[0].event
        assert_equal "assigned", @issue.events[1].event
      end

      test "generates an event for removing multiple assignees" do
        @issue.assignees = [@owner, @collaborator]
        @issue.save

        assert_difference "@issue.events.count", 1 do
          # Removes @owner as an assignee
          @issue.assignees = [@collaborator]
          @issue.save
        end

        assert_equal "unassigned", @issue.events.last.event
      end

      test "generates events when single assignee is swapped" do
        org = create :organization, admin: @owner, plan: "free"
        repo = create :private_repository, owner: org
        issue = create :issue, repository: repo, user: @owner
        user = create :user
        repo.add_member user

        issue.assignees = [@owner]

        assert_equal "assigned", issue.events.last.event
        assert issue.events.find_by(event: "assigned", actor_id: @owner.id).present?

        refute issue.events.find_by(event: "unassigned", actor_id: @owner.id).present?
        refute issue.events.find_by(event: "assigned", actor_id: user.id).present?

        # swap the assignees and remove the old assignee
        issue.assignees = [user, @owner]

        assert issue.events.find_by(event: "unassigned", actor_id: @owner.id).present?
        assert issue.events.find_by(event: "assigned", actor_id: user.id).present?
      end
    end

    context "assignment permissions" do
      test "assigning issue to collaborator" do
        assert_nil @issue.assignee
        @issue.assignee = @collaborator
        @issue.save
        assert_equal @collaborator, @issue.assignee
      end

      test "can't assign issue to non-collaborator" do
        assert !@repo.members.include?(@unauthed)
        assert !@issue.assignee
        issue = Issue.new repository: @repo, user: @owner, assignee: @unauthed, title: "a title"
        issue.save
        assert issue.errors[:assignee].any?
      end
    end

    context "assignee deletion cleanup" do
      test "the issue's assignee_id is set to another assignee's ID if there is one" do
        @issue.assignees = [@collaborator, @owner]
        @issue.save
        @issue.reload

        assert_equal @collaborator.id, @issue.assignee_id

        @collaborator.destroy
        @issue.reload

        assert_equal @owner.id, @issue.assignee_id
      end

      test "the issue's assignee_id is cleared if the deleted user was the only assignee" do
        @issue.assignees = [@collaborator]
        @issue.save
        @issue.reload

        assert_equal @collaborator.id, @issue.assignee_id

        @collaborator.destroy
        @issue.reload

        assert_nil @issue.assignee_id
      end
    end

    context "hydro events" do
      test "send hydro event when an assignee is added" do
        @issue.assignees = [@collaborator]

        assert_hydro_published(
          issue_update_assignee_message(issue: @issue, actor: @owner, assignees: [@collaborator], action: "issue.events.assigned"),
          schema: "github.v1.IssueUpdateAssignee")
      end

      test "send hydro event when assignees are added" do
        Timecop.freeze do
          @issue.assignees = [@collaborator, @owner]
        end

        assert_hydro_published(
          issue_update_assignee_message(issue: @issue, actor: @owner, assignees: [@owner, @collaborator], action: "issue.events.assigned"),
          schema: "github.v1.IssueUpdateAssignee")
      end

      test "send hydro event when an assignee is removed" do
        Timecop.freeze do
          @issue.assignees = [@collaborator, @owner]
          @issue.assignees = [@owner]
        end

        assert_hydro_published(
          issue_update_assignee_message(issue: @issue, actor: @owner, assignees: [@owner], action: "issue.events.unassigned"),
          schema: "github.v1.IssueUpdateAssignee")
      end

      test "send hydro event when assignees are removed" do
        Timecop.freeze do
          @issue.assignees = [@collaborator, @owner]
          @issue.assignees = []
        end

        assert_hydro_published(
          issue_update_assignee_message(issue: @issue, actor: @owner, assignees: [], action: "issue.events.unassigned"),
          schema: "github.v1.IssueUpdateAssignee",
          count: 2
        )
      end
    end
  end

  def issue_update_assignee_message(issue:, actor:, assignees:, action:)
    {
      actor: Hydro::EntitySerializer.user(actor),
      issue: Hydro::EntitySerializer.issue(issue),
      repository: Hydro::EntitySerializer.repository(issue.repository),
      assignees: Hydro::EntitySerializer.users(assignees),
      action: action
    }
  end
end

class IssueAssigneeLimitValidationsTest < GitHub::TestCase
  fixtures do
    @owner                = create(:user, login: "owner")
    @other_user           = create(:user)
    @private_repo         = create(:private_repository, owner: @owner)
    @private_issue        = create(:issue, repository: @private_repo, user: @private_repo.owner)


    @free_org               = create(:free_organization, admin: @owner)
    @free_org_private_repo  = create(:private_repository, owner: @free_org)
    @free_org_private_issue = create(:issue, repository: @free_org_private_repo, user: @owner)

    @paid_org               = create(:business_plus_organization, admin: @owner)
    @paid_org_private_repo  = create(:private_repository, owner: @paid_org)
    @paid_org_private_issue = create(:issue, repository: @paid_org_private_repo, user: @owner)
  end

  context("IssueAssigneeLimitValidations") do
    context "issue on private repo for user account" do
      test "valid with less than plan limit" do
        @private_repo.add_member @other_user

        @private_issue.assignees << [@owner, @other_user]
        assert @private_issue.valid?
      end

      test "invalid for more than plan limit" do
        too_many_assignees = 3.times.map do
          create(:user).tap do |user|
            @private_repo.add_member user
          end
        end

        @private_issue.repository.stubs(:plan_limit).with(:issue_pr_assignees).returns(2)
        @private_issue.assignees << too_many_assignees

        refute @private_issue.valid?
      end
    end

    context "issue on private repo for free org account" do
      test "valid with 1 assignee" do
        @free_org_private_issue.assignees << @owner
        assert @free_org_private_issue.valid?
      end

      test "invalid with more than 1 assignee" do
        @free_org_private_repo.add_member @other_user

        @free_org_private_issue.assignees << [@owner, @other_user]
        refute @free_org_private_issue.valid?
      end
    end

    context "issue on private repo for paid org account" do
      test "valid for less than plan limit" do
        @paid_org_private_issue.assignees = [@owner]
        assert @paid_org_private_issue.valid?
      end

      test "invalid for more than plan limit" do
        too_many_assignees = 3.times.map do
          create(:user).tap do |user|
            @paid_org_private_repo.add_member user
          end
        end

        @paid_org_private_issue.repository.stubs(:plan_limit).with(:issue_pr_assignees).returns(2)
        @paid_org_private_issue.assignees << too_many_assignees

        refute @paid_org_private_issue.valid?
      end
    end

    context "private repo transfered from user account to free org account" do
      test "valid for unchanged list of assignees" do
        @private_repo.add_member @other_user

        @private_issue.assignees << [@owner, @other_user]
        assert @private_issue.valid?

        @private_issue.save!

        @private_repo.transfer_ownership_to(@free_org, actor: @owner)
        assert_equal @free_org, @private_repo.reload.owner

        @private_issue.title = "Watch this space"
        assert @private_issue.valid?
      end

      test "invalid for changed list of assignees" do
        @private_repo.add_member @other_user

        @private_issue.assignees << [@owner, @other_user]

        assert_equal @private_issue.assignee_limit, 10
        assert @private_issue.valid?

        @private_issue.save!

        @private_repo.transfer_ownership_to(@free_org, actor: @owner)
        assert_equal @free_org, @private_repo.reload.owner

        # bypass issue assignee_limit memoization which preserves value of previous plan_limit
        @private_issue = Issue.find(@private_issue.id)

        another_user = create(:user)
        @private_repo.add_member another_user

        @private_issue.assignees << another_user

        assert_equal @private_issue.assignee_limit, 1
        refute @private_issue.valid?
      end
    end
  end
end

class IssueAvailableAssigneeIdsTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "owner")
    @other_user = create(:user)

    @business = create(:business)
    @org = create(:organization, admin: @owner, business: @business)
    @org.update_default_repository_permission(:none, actor: @owner)

    @org.add_member(@other_user)

    @paid_org_internal_repo = create(:internal_repository, owner: @org)
    @paid_org_internal_issue = create(:issue, repository: @paid_org_internal_repo, user: @owner)

    @paid_org_private_repo = create(:private_repository, owner: @org)
    @paid_org_private_issue = create(:issue, repository: @paid_org_private_repo, user: @owner)
  end

  context("IssueAvailableAssigneeIds") do
    test "returns correct ids for internal repo", skip_if_feature_disabled: :available_assignee_ids_with_repo_read_access do
      assert_same_elements [@owner, @other_user].map(&:id), @paid_org_internal_issue.available_assignee_ids
    end

    test "returns correct ids for private repo" do
      assert_same_elements [@owner.id], @paid_org_private_issue.available_assignee_ids
    end
  end
end
