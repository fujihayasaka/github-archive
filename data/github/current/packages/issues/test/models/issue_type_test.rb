# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueTypeTest < GitHub::TestCase
  include HydroTestHelpers
  include Issues::Domain::Provider

  fixtures do
    GitHub.flipper[:issue_types].enable
  end

  test "can create issue type" do
    owner = create(:organization)
    issue_type = create(:issue_type,
      owner: owner,
      name: "test",
      description: "this is the description",
      private: true
    )

    assert issue_type.persisted?

    issue_type.reload
    assert_equal owner, issue_type.owner
    assert_equal "test", issue_type.name
    assert_equal "gray", issue_type.color
    assert_equal "this is the description", issue_type.description
    assert issue_type.private?
    assert issue_type.enabled
  end

  context "create" do
    test "validates require fields" do
      issue_type = IssueType.new
      refute_predicate issue_type, :valid?
      [:owner_id, :name].each do |field|
        assert_includes issue_type.errors[field], "can't be blank"
      end
    end

    test "name cannot be too long" do
      issue_type = IssueType.new(name: "A" * (::IssueType::NAME_LENGTH_LIMIT + 1))
      refute_predicate issue_type, :valid?
      assert_includes issue_type.errors[:name], "is too long (maximum is 64 characters)"
    end

    test "name cannot be reserved" do
      IssueType::RESERVED_NAMES.each do |name|
        issue_type = IssueType.new(name: name.titleize)
        refute_predicate issue_type, :valid?
        assert_includes issue_type.errors[:name], "is reserved"
      end
    end

    test "name is stripped of whitespace" do
      issue_type = create(:issue_type, name: "  test ")
      assert_equal "test", issue_type.name
    end

    test "cannot use a reserved name by adding whitespace" do
      assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Name is reserved") do
        create(:issue_type,  name: IssueType::RESERVED_NAMES.first.titleize + "  ")
      end
    end

    test "description cannot be too long" do
      issue_type = IssueType.new(description: "A" * (::IssueType::DESCRIPTION_LENGTH_LIMIT + 1))
      refute_predicate issue_type, :valid?
      assert_includes issue_type.errors[:description], "is too long (maximum is 256 characters)"
    end

    test "cannot create duplicate named types for an owner" do
      owner = create(:organization)
      create(:issue_type, owner: owner, name: "test")
      assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Name has already been taken") do
        create(:issue_type, owner: owner, name: "test")
      end
    end

    test "different owners can have the same named type" do
      create(:issue_type, name: "test")
      same_name = create(:issue_type, name: "test")
      assert_predicate same_name, :persisted?
    end

    test "does not create issue type when limit is reached" do
      user = create(:verified_user)
      org = create(:organization, admin: user)

      org.issue_types.count..IssueType::ORGANIZATION_ISSUE_TYPES_LIMIT.times do
        create(:issue_type, owner: org, enabled: true)
      end

      org.reload

      issue_type = IssueType.new(owner: org, name: "exceeding limit", enabled: true)

      refute_predicate issue_type, :valid?
      assert_includes issue_type.errors[:base], "Maximum number of issue types is reached for this organization"
    end

    test "does not create issue type when owner is a user" do
      issue_type = IssueType.new(owner: create(:verified_user), name: "owner invalid", enabled: true)

      refute_predicate issue_type, :valid?
      assert_includes issue_type.errors[:owner], "Owner must be an organization"
    end
  end

  context "update" do
    test "validates require fields" do
      model = create(:issue_type)

      [:owner_id, :name, :enabled].each do |field|
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

  context "user" do
    test "can load issue_types via domain" do
      org = create(:organization)
      assert_equal 3, issues_domain.issue_types.by_organizations([org])[org.id]&.count
    end
  end

  context "issue" do
    test "can load issue_type via association" do
      owner = create(:organization)
      issue_type = owner.issue_types.find_by(name: IssueType::DEFAULTS.first[:name])
      repo = create(:repository, owner: owner)
      issue = create(:issue, user: owner.members.first, repository: repo, issue_type: issue_type)

      assert_equal issue_type, issue.reload.issue_type
    end
  end

  context "default types" do
    test "creates default types if missing for an organization" do
      owner = create(:organization, exclude_issue_types: true)
      assert_empty owner.issue_types

      # 1 to check existance
      # 1 to update
      assert_query_count_per_table({ issue_types: 2 }) do
        IssueType.create_default_issue_types_for(owner)
      end

      assert_equal 3, owner.reload.issue_types.count
    end

    test "creates default types if missing in multiple organizations using 1 query" do
      owners = 5.times.map do
        owner = create(:organization, exclude_issue_types: true)

        assert_empty owner.issue_types

        owner
      end

      # 1 to check existance
      # 1 to update
      assert_query_count_per_table({ issue_types: 2 }) do
        IssueType.create_default_issue_types_for(owners)
      end

      owners.each { |owner| assert_equal 3, owner.reload.issue_types.count }
    end

    test "make sure it does not duplicate an existing type" do
      owner = create(:organization, exclude_issue_types: true)
      created_type = create(:issue_type, owner: owner, name: "Bug", enabled: false, description: "bug description")

      IssueType.create_default_issue_types_for(owner)

      bug_types = owner.reload.issue_types.where(name: "bug")

      assert_equal 1, bug_types.count

      bug_type = bug_types.first

      assert_equal created_type.id, bug_type.id
      assert_equal created_type.enabled?, bug_type.enabled?
      assert_equal 3, owner.issue_types.count
    end

    test "default types have correct values" do
      owner = create(:organization)

      assert_equal 3, owner.issue_types.count

      IssueType::DEFAULTS.each do |default|
        issue_type = owner.issue_types.find_by(name: default[:name])
        assert_equal default[:color].to_s, issue_type.color
        assert_equal default[:description], issue_type.description
      end
    end
  end

  context "search" do
    test "triggers issues indexing when name or enabled is changed" do
      model = create(:issue_type)
      expected_args = ->(job_args) do
        named = job_args.first
        assert_equal :issue_type, named[:association_name]
        assert_equal model.id, named[:association_id]
      end

      model.name = "changed"
      assert_enqueued_with job: Issues::ReindexIssuesForAssociationJob, args: expected_args  do
        model.save
      end

      model.enabled = !model.enabled
      assert_enqueued_with job: Issues::ReindexIssuesForAssociationJob, args: expected_args do
        model.save
      end
    end

    test "triggers issue indexing when destroyed" do
      model = create(:issue_type)
      expected_args = ->(job_args) do
        named = job_args.first
        assert_equal :issue_type, named[:association_name]
        assert_equal model.id, named[:association_id]
      end

      assert_enqueued_with job: Issues::ReindexIssuesForAssociationJob, args: expected_args do
        model.destroy
      end
    end

    test "does not trigger issues indexing when other fields change" do
      model = create(:issue_type)

      model.description = "test"
      assert_enqueued_jobs 0, only: Issues::ReindexIssuesForAssociationJob do
        model.save
      end
    end
  end

  context "memex_column_hash" do
    test "returns hash representation of the issue type" do
      model = create(:issue_type)

      assert_equal(
        {
          id: model.id,
          name: model.name,
          description: model.description,
          color: model.color.upcase,
        },
        model.memex_column_hash
      )
    end
  end

  context "#memex_suggestion_hash" do
    test "returns hash representation of the issue type with selection" do
      model = create(:issue_type)

      assert_equal(
        {
          id: model.id,
          name: model.name,
          description: model.description,
          color: model.color.upcase,
          selected: true,
        },
        model.memex_suggestion_hash(selected: true)
      )
    end
  end

  context "hydro events" do
    test "after create publishes github.v1.IssueTypeCreate" do
      freeze_time

      admin = create(:verified_user)
      organization = create(:organization, admin: admin)

      GitHub.context.push(actor_id: admin.id)

      assert_no_hydro_message_difference "github.v1.IssueTypeUpdate" do
        assert_no_hydro_message_difference "github.v1.IssueTypeDestroy" do
          issue_type = create(:issue_type, owner: organization)

          expected_hydro_payload = {
            actor: Hydro::EntitySerializer.user(admin),
            issue_type: Hydro::EntitySerializer.issue_type(issue_type),
          }

          assert_hydro_published(expected_hydro_payload, schema: "github.v1.IssueTypeCreate", count: 1)
        end
      end
    end

    test "after create without actor uses ghost user" do
      freeze_time

      admin = create(:verified_user)
      organization = create(:organization, admin: admin)
      issue_type = create(:issue_type, owner: organization)

      expected_hydro_payload = {
        actor: Hydro::EntitySerializer.user(User.ghost),
        issue_type: Hydro::EntitySerializer.issue_type(issue_type),
      }

      assert_nil GitHub.context[:actor_id], "Expected actor to be reset after update"
      assert_hydro_published(expected_hydro_payload, schema: "github.v1.IssueTypeCreate", count: 1)
    end

    test "after update publishes github.v1.IssueTypeUpdate" do
      freeze_time

      admin = create(:verified_user)
      organization = create(:organization, admin: admin)
      issue_type = create(:issue_type, owner: organization)

      GitHub.context.push(actor_id: admin.id)

      assert_no_hydro_message_difference "github.v1.IssueTypeCreate" do
        assert_no_hydro_message_difference "github.v1.IssueTypeDestroy" do
          issue_type.update!(name: "new name")
        end
      end

      expected_hydro_payload = {
        actor: Hydro::EntitySerializer.user(admin),
        issue_type: Hydro::EntitySerializer.issue_type(issue_type),
      }

      assert_hydro_published(expected_hydro_payload, schema: "github.v1.IssueTypeUpdate", count: 1)
    end

    test "after update without actor uses ghost user" do
      freeze_time

      admin = create(:verified_user)
      organization = create(:organization, admin: admin)
      issue_type = create(:issue_type, owner: organization)
      issue_type.update!(name: "new name")

      expected_hydro_payload = {
        actor: Hydro::EntitySerializer.user(User.ghost),
        issue_type: Hydro::EntitySerializer.issue_type(issue_type),
      }

      assert_nil GitHub.context[:actor_id], "Expected actor to be reset after update"
      assert_hydro_published(expected_hydro_payload, schema: "github.v1.IssueTypeUpdate", count: 1)
    end

    test "after destroying issue type publishes github.v1.IssueTypeDestroy" do
      freeze_time

      admin = create(:verified_user)
      organization = create(:organization, admin: admin)
      issue_type = create(:issue_type, owner: organization)

      GitHub.context.push(actor_id: admin.id)

      assert_no_hydro_message_difference "github.v1.IssueTypeCreate" do
        assert_no_hydro_message_difference "github.v1.IssueTypeUpdate" do
          issue_type.destroy!
        end
      end

      expected_hydro_payload = {
        actor: Hydro::EntitySerializer.user(admin),
        issue_type: Hydro::EntitySerializer.issue_type(issue_type),
      }

      assert_hydro_published(expected_hydro_payload, schema: "github.v1.IssueTypeDestroy", count: 1)
    end

    test "after destroy without actor uses ghost user" do
      freeze_time

      admin = create(:verified_user)
      organization = create(:organization, admin: admin)
      issue_type = create(:issue_type, owner: organization)
      issue_type.destroy!

      expected_hydro_payload = {
        actor: Hydro::EntitySerializer.user(User.ghost),
        issue_type: Hydro::EntitySerializer.issue_type(issue_type),
      }

      assert_nil GitHub.context[:actor_id], "Expected actor to be reset after update"
      assert_hydro_published(expected_hydro_payload, schema: "github.v1.IssueTypeDestroy", count: 1)
    end
  end
end
