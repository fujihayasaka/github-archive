# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryIssueTypeTest < GitHub::TestCase
  include HydroTestHelpers

  test "can create repository issue type" do
    model = create(:repository_issue_type)
    assert model.persisted?
  end

  context "create" do
    test "validates required fields" do
      model = RepositoryIssueType.new
      refute_predicate model, :valid?
      [:repository, :issue_type].each do |field|
        assert_includes model.errors[field], "can't be blank"
      end
    end

    test "cannot create duplicate types for a repository" do
      owner = create(:organization)
      issue_type = create(:issue_type, owner: owner)
      repo = create(:repository, owner: owner)
      create(:repository_issue_type, repository: repo, issue_type: issue_type)
      assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Issue type has already been taken") do
        create(:repository_issue_type, repository: repo, issue_type: issue_type)
      end
    end

    test "different repositories can have the same type" do
      owner = create(:organization)
      issue_type = create(:issue_type, owner: owner)
      create(:repository_issue_type, issue_type: issue_type)
      same_type = create(:repository_issue_type, issue_type: issue_type)
      assert_predicate same_type, :persisted?
    end

    test "must have same repository owner as the issue type" do
      issue_type = create(:issue_type, owner: create(:organization))
      repo = create(:repository, owner: create(:organization))
      assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Repository must be owned by issue type owner") do
        create(:repository_issue_type, repository: repo, issue_type: issue_type)
      end
    end

    test "must have an enabled issue type when enabling the repository issue type" do
      owner = create(:organization)
      issue_type = create(:issue_type, owner: owner, enabled: false)
      repo = create(:repository, owner: owner)
      assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Issue type must exist and be enabled by the issue type owner") do
        create(:repository_issue_type, repository: repo, issue_type: issue_type, enabled: true)
      end

      disabled_repo_issue_type = create(:repository_issue_type, repository: repo, issue_type: issue_type, enabled: false)
      assert_predicate disabled_repo_issue_type, :persisted?
    end
  end

  context "update" do
    test "validates require fields" do
      model = create(:repository_issue_type)

      [:repository, :issue_type, :enabled].each do |field|
        assert_predicate model, :valid?
        original_value = model.send(field)

        model.send("#{field}=", nil)
        success = model.save
        refute success
        assert_includes model.errors[field], "can't be blank"

        model.send("#{field}=", original_value)
      end
    end
  end

  context "search" do
    test "triggers issues indexing when name or enabled is changed" do
      owner = create(:organization)
      repo = create(:repository, owner: owner)
      issue_type = owner.issue_types.find_by(name: IssueType::DEFAULTS.first[:name])
      model = create(:repository_issue_type, issue_type: issue_type, repository: repo)

      expected_args = ->(job_args) do
        named = job_args.first
        assert_equal :issue_type, named[:association_name]
        refute_nil named[:association_id]
      end

      model.enabled = !model.enabled
      assert_enqueued_with job: Issues::ReindexIssuesForAssociationJob, args: expected_args do
        assert_enqueued_jobs 3, only: Issues::ReindexIssuesForAssociationJob do
          model.save
        end
      end
    end

    test "triggers issues index when created or destroyed" do
      owner = create(:organization)
      repo = create(:repository, owner: owner)

      expected_args = ->(job_args) do
        named = job_args.first
        assert_equal :issue_type, named[:association_name]
        assert_equal :repository_id, named[:sharding_key]
        assert_equal repo.id, named[:sharding_key_value]
        refute_nil named[:association_id]
      end

      second_issue_type = owner.issue_types.find_by(name: IssueType::DEFAULTS.second[:name])
      assert_enqueued_with job: Issues::ReindexIssuesForAssociationJob, args: expected_args do
        assert_enqueued_jobs 3, only: Issues::ReindexIssuesForAssociationJob do
          create(:repository_issue_type, repository: repo, issue_type: second_issue_type)
        end
      end

      third_issue_type = owner.issue_types.find_by(name: IssueType::DEFAULTS.third[:name])
      third_repo_issue_type = create(:repository_issue_type, repository: repo, issue_type: third_issue_type)
      assert_enqueued_with job: Issues::ReindexIssuesForAssociationJob, args: expected_args do
        assert_enqueued_jobs 3, only: Issues::ReindexIssuesForAssociationJob do
          third_repo_issue_type.destroy!
        end
      end
    end
  end

  context "hydro events" do
    test "after create publishes github.v1.RepositoryIssueTypeCreate" do
      freeze_time

      admin = create(:verified_user)
      organization = create(:organization, admin: admin)
      repository = create(:repository, owner: organization)
      issue_type = create(:issue_type, owner: organization)

      GitHub.context.push(actor_id: admin.id)

      assert_no_hydro_message_difference "github.v1.RepositoryIssueTypeUpdate" do
        assert_no_hydro_message_difference "github.v1.RepositoryIssueTypeDestroy" do
          repository_issue_type = create(:repository_issue_type, repository: repository, issue_type: issue_type, enabled: false)

          expected_hydro_payload = {
            actor: Hydro::EntitySerializer.user(admin),
            repository: Hydro::EntitySerializer.repository(repository),
            issue_type: Hydro::EntitySerializer.issue_type(issue_type),
            enabled: false,
          }

          assert_hydro_published(expected_hydro_payload, schema: "github.v1.RepositoryIssueTypeCreate", count: 1)
        end
      end
    end

    test "after create without actor uses ghost user" do
      freeze_time

      admin = create(:verified_user)
      organization = create(:organization, admin: admin)
      repository = create(:repository, owner: organization)
      issue_type = create(:issue_type, owner: organization)
      repository_issue_type = create(:repository_issue_type, repository: repository, issue_type: issue_type, enabled: false)

      expected_hydro_payload = {
        actor: Hydro::EntitySerializer.user(User.ghost),
        repository: Hydro::EntitySerializer.repository(repository),
        issue_type: Hydro::EntitySerializer.issue_type(issue_type),
        enabled: false,
      }

      assert_nil GitHub.context[:actor_id], "Expected actor to be reset after update"
      assert_hydro_published(expected_hydro_payload, schema: "github.v1.RepositoryIssueTypeCreate", count: 1)
    end

    test "after update publishes github.v1.IssueTypeUpdate" do
      freeze_time

      admin = create(:verified_user)
      organization = create(:organization, admin: admin)
      repository = create(:repository, owner: organization)
      issue_type = create(:issue_type, owner: organization)
      repository_issue_type = create(:repository_issue_type, repository: repository, issue_type: issue_type, enabled: false)

      GitHub.context.push(actor_id: admin.id)

      assert_no_hydro_message_difference "github.v1.RepositoryIssueTypeCreate" do
        assert_no_hydro_message_difference "github.v1.RepositoryIssueTypeDestroy" do
          repository_issue_type.update!(enabled: true)
        end
      end

      expected_hydro_payload = {
        actor: Hydro::EntitySerializer.user(admin),
        repository: Hydro::EntitySerializer.repository(repository),
        issue_type: Hydro::EntitySerializer.issue_type(issue_type),
        enabled: true,
      }

      assert_hydro_published(expected_hydro_payload, schema: "github.v1.RepositoryIssueTypeUpdate", count: 1)
    end

    test "after update without actor uses ghost user" do
      freeze_time

      admin = create(:verified_user)
      organization = create(:organization, admin: admin)
      repository = create(:repository, owner: organization)
      issue_type = create(:issue_type, owner: organization)
      repository_issue_type = create(:repository_issue_type, repository: repository, issue_type: issue_type, enabled: false)
      repository_issue_type.update!(enabled: true)

      expected_hydro_payload = {
        actor: Hydro::EntitySerializer.user(User.ghost),
        repository: Hydro::EntitySerializer.repository(repository),
        issue_type: Hydro::EntitySerializer.issue_type(issue_type),
        enabled: true,
      }

      assert_nil GitHub.context[:actor_id], "Expected actor to be reset after update"
      assert_hydro_published(expected_hydro_payload, schema: "github.v1.RepositoryIssueTypeUpdate", count: 1)
    end

    test "after destroying issue type publishes github.v1.IssueTypeDestroy" do
      freeze_time

      admin = create(:verified_user)
      organization = create(:organization, admin: admin)
      repository = create(:repository, owner: organization)
      issue_type = create(:issue_type, owner: organization)
      repository_issue_type = create(:repository_issue_type, repository: repository, issue_type: issue_type, enabled: false)

      GitHub.context.push(actor_id: admin.id)

      assert_no_hydro_message_difference "github.v1.RepositoryIssueTypeCreate" do
        assert_no_hydro_message_difference "github.v1.RepositoryIssueTypeUpdate" do
          repository_issue_type.destroy!
        end
      end

      expected_hydro_payload = {
        actor: Hydro::EntitySerializer.user(admin),
        repository: Hydro::EntitySerializer.repository(repository),
        issue_type: Hydro::EntitySerializer.issue_type(issue_type),
        enabled: false,
      }

      assert_hydro_published(expected_hydro_payload, schema: "github.v1.RepositoryIssueTypeDestroy", count: 1)
    end

    test "after destroy without actor uses ghost user" do
      freeze_time

      admin = create(:verified_user)
      organization = create(:organization, admin: admin)
      repository = create(:repository, owner: organization)
      issue_type = create(:issue_type, owner: organization)
      repository_issue_type = create(:repository_issue_type, repository: repository, issue_type: issue_type, enabled: false)
      repository_issue_type.destroy!

      expected_hydro_payload = {
        actor: Hydro::EntitySerializer.user(User.ghost),
        repository: Hydro::EntitySerializer.repository(repository),
        issue_type: Hydro::EntitySerializer.issue_type(issue_type),
        enabled: false,
      }

      assert_nil GitHub.context[:actor_id], "Expected actor to be reset after update"
      assert_hydro_published(expected_hydro_payload, schema: "github.v1.RepositoryIssueTypeDestroy", count: 1)
    end
  end
end
