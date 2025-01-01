# typed: true
# frozen_string_literal: true

require "test_helper"

class ClassroomAssignmentRepositoryBuilderTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
    @source_org = create(:organization, admin: @user)
    @source_repo = create(:private_repository, owner: @source_org, from_example: :simple)
    @source_assignment = create(:classroom_assignment, starter_code_repository_id: @source_repo.id)

    @target_org = create(:organization, admin: @user)
    @target_assignment = create(:classroom_assignment)

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  context "builds new repository" do
    test "that is a database clone of the starter repository" do
      repo = ClassroomAssignment::RepositoryBuilder.perform(@target_assignment, @source_repo, @source_org.admins.first, @target_org)
      repo.save!
      repo.reload

      assert_equal repo.name, @source_repo.name
      assert_equal repo.owner, @target_org
      assert repo.private?
    end

    test "that is empty because cloning happens in the twirp end point and not on repo save" do
      repo = ClassroomAssignment::RepositoryBuilder.perform(@target_assignment, @source_repo, @source_org.admins.first, @target_org)
      repo.save!
      repo.reload

      assert_equal repo.name, @source_repo.name
      assert_equal repo.owner, @target_org
      refute_equal repo.refs.find("master")&.target_oid, @source_repo.refs.find("master").target_oid
      refute_equal repo.empty?, @source_repo.empty?
    end

    test "it does not enqueue a RepositoryCloneJob" do
      assert_no_enqueued_jobs(only: RepositoryCloneJob) do
        ClassroomAssignment::RepositoryBuilder.perform(@target_assignment, @source_repo, @source_org.admins.first, @target_org)
      end
    end
  end

  context "validations" do
    test "raises an error if classroom_assignment is nil" do
      assert_raises(ArgumentError) do
        ClassroomAssignment::RepositoryBuilder.perform(nil, @source_repo, @source_org.admins.first, @target_org)
      end
    end

    test "raises an error if source_repo is nil" do
      assert_raises(ArgumentError) do
        ClassroomAssignment::RepositoryBuilder.perform(@target_assignment, nil, @source_org.admins.first, @target_org)
      end
    end

    test "raises an error if actor is nil" do
      assert_raises(ArgumentError) do
        ClassroomAssignment::RepositoryBuilder.perform(@target_assignment, @source_repo, nil, @target_org)
      end
    end

    test "raises an error if org is nil" do
      assert_raises(ArgumentError) do
        ClassroomAssignment::RepositoryBuilder.perform(@target_assignment, @source_repo, @source_org.admins.first, nil)
      end
    end
  end

  context "creation errors" do
    test "repo error" do
      result = Repository::Creatable::Result.new(false, false, Repository.new, "Failure")
      Repository.stubs(:handle_creation).returns(result)

      assert_raises ClassroomAssignment::RepositoryBuilder::FailedRepositoryCreationError do
        ClassroomAssignment::RepositoryBuilder.perform(@target_assignment, @source_repo, @source_org.admins.first, @target_org)
      end
    end

    test "classroom error" do
      ClassroomAssignment.any_instance.stubs(:save).returns(false)

      assert_raises ClassroomAssignment::RepositoryBuilder::FailedRepositoryCreationError do
        ClassroomAssignment::RepositoryBuilder.perform(@target_assignment, @source_repo, @source_org.admins.first, @target_org)
      end
    end
  end

  test "copies repository license" do
    mit_license = License.find("mit")
    @source_repo.create_repository_license(license_id: mit_license.id)

    repo = ClassroomAssignment::RepositoryBuilder.perform(@target_assignment, @source_repo, @source_org.admins.first, @target_org)
    repo.save!
    repo.reload

    assert_equal repo.repository_license.license_id, mit_license.id
  end

  test "queues RepositoryCopyLanguageStatsJob" do
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      assert_enqueued_with(job: RepositoryCopyLanguageStatsJob) do
        ClassroomAssignment::RepositoryBuilder.perform(@target_assignment, @source_repo, @source_org.admins.first, @target_org)
      end
    end
  end
end
