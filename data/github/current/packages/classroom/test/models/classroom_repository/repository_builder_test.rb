# typed: true
# frozen_string_literal: true

require "test_helper"

class ClassroomRepositoryRepositoryBuilderTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @org = create :organization

    @starter_repo = create :repository, owner: @org, from_example: :simple

    make_trusted_oauth_apps_owner
    @classroom = create :classroom_integration
    make_integration_installation(integration: @classroom, target: @org)
  end

  attr_reader :org, :starter_repo, :classroom

  context "builds new repository" do
    test "that is a clone of the starter repository" do
      assignment = create :classroom_assignment, starter_code_repository: starter_repo
      classroom_repo = build :classroom_repository, repository: nil, assignment: assignment
      repo = ClassroomRepository::RepositoryBuilder.perform(classroom_repo, classroom.bot, org, "test 1", true, starter_repo)
      classroom_repo.save!
      repo.reload

      assert_equal repo.name, "test-1"
      assert_equal repo.owner, org
      assert repo.private?
      assert_equal starter_repo, ClassroomRepository.find_by!(repository: repo).starter_code_repository
    end

    test "that is empty if no starter repository" do
      classroom_repo = build :classroom_repository, repository: nil
      repo = ClassroomRepository::RepositoryBuilder.perform(classroom_repo, classroom.bot, org, "test 1", false, nil).tap(&:save!)
      repo.reload

      assert_equal repo.name, "test-1"
      assert_equal repo.owner, org
      refute repo.private?
      assert_nil ClassroomRepository.find_by!(repository: repo).starter_code_repository
    end
  end

  context "RepositoryCloneJob" do
    test "enqueues job if starter repository present" do
      assignment = create :classroom_assignment, starter_code_repository: starter_repo
      classroom_repo = build :classroom_repository, repository: nil, assignment: assignment
      assert_enqueued_with(job: RepositoryCloneJob) do
        ClassroomRepository::RepositoryBuilder.perform(classroom_repo, classroom.bot, org, "test 1", true, starter_repo).tap(&:save!)
      end
    end

    test "does not enqueue job if no starter repository" do
      classroom_repo = build :classroom_repository, repository: nil
      assert_no_enqueued_jobs(only: RepositoryCloneJob) do
        ClassroomRepository::RepositoryBuilder.perform(classroom_repo, classroom.bot, org, "test 1", true, nil).tap(&:save!)
      end
    end
  end

  context "validations" do
    test "raises an error if classroom_repo is nil" do
      assert_raises(ArgumentError) do
        ClassroomRepository::RepositoryBuilder.perform(nil, classroom.bot, org, "test 1", true, nil).tap(&:save!)
      end
    end

    test "raises an error if actor is nil" do
      classroom_repo = build :classroom_repository, repository: nil
      assert_raises(ArgumentError) do
        ClassroomRepository::RepositoryBuilder.perform(classroom_repo, nil, org, "test 1", true, nil).tap(&:save!)
      end
    end

    test "raises an error if organization is nil" do
      classroom_repo = build :classroom_repository, repository: nil
      assert_raises(ArgumentError) do
        ClassroomRepository::RepositoryBuilder.perform(classroom_repo, classroom.bot, nil, "test 1", true, nil).tap(&:save!)
      end
    end

    test "raises an error if repo_name is nil" do
      classroom_repo = build :classroom_repository, repository: nil
      assert_raises(ArgumentError) do
        ClassroomRepository::RepositoryBuilder.perform(classroom_repo, classroom.bot, org, nil, true, nil).tap(&:save!)
      end
    end

    test "raises an error if is_private is nil" do
      classroom_repo = build :classroom_repository, repository: nil
      assert_raises(ArgumentError) do
        ClassroomRepository::RepositoryBuilder.perform(classroom_repo, classroom.bot, org, "test 1", nil, nil).tap(&:save!)
      end
    end
  end

  test "copies repository license" do
    mit_license = License.find("mit")
    starter_repo.create_repository_license(license_id: mit_license.id)

    assignment = create :classroom_assignment, starter_code_repository: starter_repo
    classroom_repo = build :classroom_repository, repository: nil, assignment: assignment
    repo = ClassroomRepository::RepositoryBuilder.perform(classroom_repo, classroom.bot, org, "test 1", false, starter_repo).tap(&:save!)
    repo.reload

    assert_equal repo.repository_license.license_id, mit_license.id
  end

  test "queues RepositoryCopyLanguageStatsJob" do
    assignment = create :classroom_assignment, starter_code_repository: starter_repo
    classroom_repo = build :classroom_repository, repository: nil, assignment: assignment
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      assert_enqueued_with(job: RepositoryCopyLanguageStatsJob) do
        ClassroomRepository::RepositoryBuilder.perform(classroom_repo, classroom.bot, org, "test 1", true, starter_repo)
      end
    end
  end
end
