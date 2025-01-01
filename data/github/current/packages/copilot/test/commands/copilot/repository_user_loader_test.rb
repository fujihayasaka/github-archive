# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::RepositoryUserLoaderTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @ruby = create(:language_name, name: "Ruby", linguist_id: 326)
  end

  context "refresh_users" do
    test "deletes orphaned users" do
      org = create(:business_plus_organization)
      org.update_default_repository_permission(:none, actor: org.admins.first)

      ranked_repo = create(:repository, owner: org, primary_language: @ruby)

      org_owner = org.admins.first
      write_collab = create(:user, login: "write-collab")
      orphan = create(:user, login: "orphan")

      ranked_repo.add_member(write_collab, action: :write)

      engaged_oss_repository = create(:copilot_engaged_oss_repository, repository: ranked_repo)
      assert_equal ranked_repo, engaged_oss_repository.repository

      org_owner_user = create(:copilot_engaged_oss_user, user: org_owner, engaged_oss_repository: engaged_oss_repository)
      assert_equal org_owner_user.repository_id, engaged_oss_repository.id

      writer_user = create(:copilot_engaged_oss_user, user: write_collab, engaged_oss_repository: engaged_oss_repository, role: "write")
      assert_equal writer_user.repository_id, engaged_oss_repository.id

      orphan_user = create(:copilot_engaged_oss_user, user: orphan, engaged_oss_repository: engaged_oss_repository, role: "write")

      assert_equal Copilot::EngagedOssUser.count, 3

      ActiveRecord::Base.connected_to(role: :reading) do
        expected_log = {
          "Body" => "Deleting existing users for repository",
          "gh.repo.id" => ranked_repo.id,
          "gh.copilot.engaged_oss_repository.id" => engaged_oss_repository.id,
        }

        assert_logged(**expected_log) do
          Copilot::RepositoryUserLoader.call(ranked_repo)
        end
      end

      assert_equal Copilot::EngagedOssUser.count, 2
      engaged_oss_user_ids = Copilot::EngagedOssUser.pluck(:id)
      refute_includes engaged_oss_user_ids, org_owner_user.id
      refute_includes engaged_oss_user_ids, writer_user.id
      refute_includes engaged_oss_user_ids, orphan_user.id

      engaged_oss_users_ids = Copilot::EngagedOssUser.pluck(:user_id)
      assert_includes engaged_oss_users_ids, org_owner.id
      assert_includes engaged_oss_users_ids, write_collab.id
      refute_includes engaged_oss_users_ids, orphan.id
    end

    test "load_users_from_repository" do
      users_with_access = Set.new
      org = create(:business_plus_organization)
      org.update_default_repository_permission(:none, actor: org.admins.first)

      org_owner = org.admins.first
      repo      = create(:repository, owner: org)
      create(:copilot_engaged_oss_repository, repository: repo, language_name: @ruby, rank: 1, fork_count: 25, stargazer_count: 500)
      users_with_access << { repository_id: repo.id, user_id: org_owner.id, language: "ruby", role: "admin" }

      write_collab = create(:user, login: "write-collab")
      users_with_access << { repository_id: repo.id, user_id: write_collab.id, language: "ruby", role: "write" }
      repo.add_member(write_collab, action: :write)

      # This will be deduped
      UserRole.create(
        actor: write_collab,
        target: repo,
        role: Role.write_role,
      )

      write_team = create(:team, organization: org, name: "write-team")
      write_team.add_repository(repo, :push)

      write_team_member = create(:user, login: "write-team-member")
      users_with_access << { repository_id: repo.id, user_id: write_team_member.id, language: "ruby", role: "write" }
      org.add_member(write_team_member)
      write_team.add_member(write_team_member)

      # This will be deduped
      UserRole.create(
        actor: write_team_member,
        target: repo,
        role: Role.write_role,
      )

      maintainer = create(:user, login: "maintainer")
      UserRole.create(
        actor: maintainer,
        target: repo,
        role: Role.maintain_role,
      )
      users_with_access << { repository_id: repo.id, user_id: maintainer.id, language: "ruby", role: "maintain" }

      writer = create(:user, login: "writer")
      UserRole.create(
        actor: writer,
        target: repo,
        role: Role.write_role,
      )
      users_with_access << { repository_id: repo.id, user_id: writer.id, language: "ruby", role: "write" }

      admin_role = create(:user, login: "admin-role")
      UserRole.create(
        actor: admin_role,
        target: repo,
        role: Role.admin_role,
      )
      users_with_access << { repository_id: repo.id, user_id: admin_role.id, language: "ruby", role: "admin" }

      custom_maintain_role = create(:custom_repository_role, :with_extra_permissions, owner_id: org.id,
        owner_type: "Organization", base_role_id: Role.maintain_role.id)

      custom_maintainer = create(:user, login: "custom-maintainer")
      UserRole.create(
        actor: custom_maintainer,
        target: repo,
        role: custom_maintain_role,
      )
      users_with_access << { repository_id: repo.id, user_id: custom_maintainer.id, language: "ruby", role: "maintain" }
      custom_write_role = create(:custom_repository_role, :with_extra_permissions, owner_id: org.id,
        owner_type: "Organization", base_role_id: Role.write_role.id)

      custom_writer = create(:user, login: "custom-writer")
      UserRole.create(
        actor: custom_writer,
        target: repo,
        role: custom_write_role,
      )
      users_with_access << { repository_id: repo.id, user_id: custom_writer.id, language: "ruby", role: "write" }

      # DOES NOT INCLUDE READERS
      read_collab = create(:user, login: "read-collab")
      repo.add_member(read_collab, action: :read)

      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::RepositoryUserLoader.call(repo)
      end

      assert_equal Copilot::EngagedOssUser.count, users_with_access.count
    end

    test "cleans up users with multiple repositories" do
      users_with_access = Set.new
      org = create(:business_plus_organization)
      org.update_default_repository_permission(:none, actor: org.admins.first)

      org_owner = org.admins.first
      repo      = create(:repository, owner: org)
      create(:copilot_engaged_oss_repository, repository: repo, language_name: @ruby, rank: 1, fork_count: 25, stargazer_count: 500)
      users_with_access << { repository_id: repo.id, user_id: org_owner.id, language: "ruby", role: "admin" }

      write_collab = create(:user, login: "write-collab")
      users_with_access << { repository_id: repo.id, user_id: write_collab.id, language: "ruby", role: "write" }
      repo.add_member(write_collab, action: :write)

      repo      = create(:repository, owner: org)
      create(:copilot_engaged_oss_repository, repository: repo, language_name: @ruby, rank: 1, fork_count: 25, stargazer_count: 500)
      repo.add_member(write_collab, action: :write)

      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::RepositoryUserLoader.call(repo)
      end
      assert_equal Copilot::EngagedOssUser.count, users_with_access.count
    end
  end
end if GitHub.copilot_enabled?
