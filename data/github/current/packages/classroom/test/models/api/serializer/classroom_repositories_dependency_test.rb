# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class ClassroomRepositorySerializersTest < Api::SerializerTestCase
  fixtures do
    @owner = create :paid_user, login: "aardwolf", id: 7653877

    @org_admin = create :user, plan: "medium", login: "laughing-hyena", id: 7617819, email: "laughing-is-life@haha.com"
    @org   = create :organization, admin: @org_admin

    @rando = create(:user)

    @repo = create :repository, owner: @owner, name: "Kunze-Smith", from_example: :simple

    @deadline = DateTime.now.new_offset(0).freeze

    classroom = create(:classroom_classroom, name: "hyena-coding-101", id: 5141981)
    assignment = create(:classroom_assignment, name: "Command Line for Hyenas", id: 8251981, deadline: @deadline.to_s, assignment_type: "group")

    classroom.instructors << create(:classroom_instructor, classroom_user: create(:classroom_user, user: @owner))
    classroom.instructors << create(:classroom_instructor, classroom_user: create(:classroom_user, user: @org_admin))

    create :classroom_repository,
      repository_id: @repo.id,
      classroom: classroom,
      assignment: assignment,
      team_id: 118675309

    @team = create :team, organization: @org, privacy: :closed, id: 118675309
    @team.add_member(@owner, adder: @org.admin)
  end

  test "returns a valid JSON schema" do
    refute_nil Api::Serializer.serialize(:classroom_repository_hash, @repo)
  end

  test "returns nil if repo is nil" do
    assert_nil Api::Serializer.serialize(:classroom_repository_hash, nil)
  end

  test "includes the classroom assignment data" do
    classroom_assignment_expected = {
      classroom_name: "hyena-coding-101",
      classroom_id: 5141981,
      assignment_name: "Command Line for Hyenas",
      assignment_id: 8251981,
      assignment_type: "group",
      team_id: 118675309,
      team_members: [{
        login: "aardwolf",
        id: 7653877,
        avatar_url: "http://alambic.github.test/avatars/u/7653877?b=1#{ TestEnv.test_all_features? ? "&jwt=#{private_avatar_jwt}" : "" }&v=2",
        email: "7653877+aardwolf@users.noreply.github.com"
      }]
    }

    expected_admins = [{
      login: "aardwolf",
      id: 7653877,
      avatar_url: "http://alambic.github.test/avatars/u/7653877?b=1#{ TestEnv.test_all_features? ? "&jwt=#{private_avatar_jwt}" : "" }&v=2",
      email: "7653877+aardwolf@users.noreply.github.com"
    },
    {
      login: "laughing-hyena",
      id: 7617819,
      avatar_url: "http://alambic.github.test/avatars/u/7617819?b=1#{ TestEnv.test_all_features? ? "&jwt=#{private_avatar_jwt}" : "" }&v=2",
      email: "laughing-is-life@haha.com"
    }]

    @owner.email_roles.each do |role|
      role.update_attribute(:public, false)
    end

    output = Api::Serializer.serialize(:classroom_repository_hash, @repo)
    actual_admins = output[:classroom_assignment].delete(:admins)
    # Delete deadline to prevent having to cast datetime to correct format
    output[:classroom_assignment].delete(:deadline)

    assert_equal classroom_assignment_expected, output[:classroom_assignment]
    assert_equal expected_admins, actual_admins.sort_by { |admin| admin[:login] }
  end

  test "when org default branch is trunk, the repo hash uses trunk as the fallback value if repo not yet online" do
    Organization.any_instance.stubs(:custom_default_new_repo_branch).returns("trunk")
    repo = create :repository, owner: @org, created_by_user_id: @org_admin.id
    # Here we stub `default_branch` to throw an exception to reproduce the way the serializer will behave
    # when we are serializing this repo just after its creation. The repo won't be online yet so we need to
    # infer its default branch by checking the owner's default branch preference.
    # This ensures that webhooks that happen on repo creation will have the proper value.
    Repository.any_instance.stubs(:default_branch).raises(GitRPC::RepositoryOffline.new("host", "path"))
    payload = Api::Serializer.serialize(:classroom_repository_hash, repo)
    assert_equal "trunk", payload[:default_branch]
  end

  test "for repositories created from a template, the repo hash uses the template's default branch as fallback value if repo not yet online" do
    template_repo = create(:repository, template: true, owner: @owner, from_example: :simple)

    renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: template_repo, branch_name: template_repo.default_branch)
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      assert renamer.start_rename("trunk", actor: @owner, entry_point: :test_case)
    end

    repo = create(:repository, owner: @owner)
    create(:repository_clone, template_repository: template_repo, clone_repository: repo)
    repo.stubs(:default_branch).raises(GitRPC::RepositoryOffline.new("host", "path"))
    payload = Api::Serializer.serialize(:classroom_repository_hash, repo)
    assert_equal "trunk", payload[:default_branch]
  end

  test "for forks, default_branch is the fork's own default branch, not its parent's" do
    repo_fork = create(:fork_repository, forker: @rando, fork_repo: @repo)

    renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: repo_fork, branch_name: repo_fork.default_branch)
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      assert renamer.start_rename("develop", actor: @owner, entry_point: :test_case)
    end

    payload = Api::Serializer.serialize(:classroom_repository_hash, repo_fork.reload)
    assert_equal "develop", payload[:default_branch]
  end

  test "for repos made from templates, default_branch is the repo's own, not the template's" do
    template_repo = create(:repository, template: true, owner: @owner, from_example: :simple)
    repo = create(:repository, owner: @owner, from_example: :simple)
    create(:repository_clone, template_repository: template_repo, clone_repository: repo)

    renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: repo, branch_name: repo.default_branch)
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      assert renamer.start_rename("develop", actor: @owner, entry_point: :test_case)
    end

    payload = Api::Serializer.serialize(:classroom_repository_hash, repo.reload)
    assert_equal "develop", payload[:default_branch]
  end

  test "populates default_branch for empty repositories" do
    result = Repository.handle_creation(@owner, @owner.login, { name: "empty-repo" })
    assert result.success
    repo = Repository.nwo("#{@owner.login}/empty-repo")
    assert repo.empty?

    output = Api::Serializer.serialize(:classroom_repository_hash, repo)
    assert_equal repo.default_branch, output[:default_branch]
  end
end
