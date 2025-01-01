# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionTimeline::AuthorRolePreloaderTest < GitHub::TestCase
  context "#action_or_role_level_for" do
    test "returns repo action/role level for author of the discussion and each comment" do
      org_admin = create(:verified_user)
      org = create(:business_plus_organization, admin: org_admin)
      org_repo = create(:repository, owner: org, has_discussions: true)

      repo_reader = create(:verified_user)
      org_repo.add_member(repo_reader, action: :read)
      repo_triager = create(:verified_user)
      org_repo.add_member(repo_triager, action: :triage)
      repo_maintainer = create(:verified_user)
      org_repo.add_member(repo_maintainer, action: :maintain)
      repo_writer = create(:verified_user)
      org_repo.add_member(repo_writer, action: :write)
      repo_admin = create(:verified_user)
      org_repo.add_member(repo_admin, action: :admin)

      org_discussion = create(:discussion, repository: org_repo)
      org_comment = create(:discussion_comment, repository: org_repo, discussion: org_discussion)
      reader_comment = org_comment
      triager_comment = create(:discussion_comment, discussion: org_discussion, user: repo_triager)
      maintainer_comment = create(:discussion_comment, discussion: org_discussion, user: repo_maintainer)
      writer_comment = create(:discussion_comment, discussion: org_discussion, user: repo_writer)
      admin_comment = create(:discussion_comment, discussion: org_discussion, user: repo_admin)

      records = [org_discussion, reader_comment, triager_comment, maintainer_comment, writer_comment, admin_comment]
      preloader = DiscussionTimeline::AuthorRolePreloader.new(
        rendered_records: records,
        repository: org_repo
      )

      assert_equal :read, preloader.action_or_role_level_for(org_discussion)
      assert_equal :read, preloader.action_or_role_level_for(reader_comment)
      assert_equal :triage, preloader.action_or_role_level_for(triager_comment)
      assert_equal :maintain, preloader.action_or_role_level_for(maintainer_comment)
      assert_equal :write, preloader.action_or_role_level_for(writer_comment)
      assert_equal :admin, preloader.action_or_role_level_for(admin_comment)
    end

    test "only makes 1 check per author" do
      repo = create(:repository, has_discussions: true)
      discussion = create(:discussion, :question, repository: repo)
      comment_user = create(:verified_user)
      comments = create_pair(:discussion_comment, user: comment_user, repository: repo, discussion: discussion)

      discussion.repository.expects(:async_action_or_role_level_for).with(
        discussion.user,
        include_employee_granted_permissions: false,
        include_custom_roles: false
      ).once.returns(Promise.resolve(:read))

      discussion.repository.expects(:async_action_or_role_level_for).with(
        comment_user,
        include_employee_granted_permissions: false,
        include_custom_roles: false
      ).once.returns(Promise.resolve(:read))

      records = [discussion] + comments
      preloader = DiscussionTimeline::AuthorRolePreloader.new(
        rendered_records: records,
        repository: repo
      )
      preloader.preload
    end

    test "can handle nil authors" do
      repo = create(:repository, has_discussions: true)
      discussion_without_user_id = create(:discussion, :question, repository: repo)
      discussion_without_user_id.user_id = nil

      preloader = DiscussionTimeline::AuthorRolePreloader.new(
        rendered_records: [discussion_without_user_id],
        repository: repo
      )
      preloader.preload

      assert_nil preloader.action_or_role_level_for(discussion_without_user_id)
    end
  end
end
