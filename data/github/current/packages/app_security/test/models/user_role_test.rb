# typed: true
# frozen_string_literal: true

require "test_helper"

class UserRoleTest < GitHub::TestCase
  fixtures do
    @organization = create(:business_plus_organization)
    @repo = create(:repository, :minimal, owner: @organization)
    @user = create(:user)
    @team = create(:team, organization: @organization, privacy: :closed)

    @triage_role = Role.triage_role
    @maintain_role = Role.maintain_role

    @custom_role = create(:custom_repository_role, :with_extra_permissions, owner_id: @organization.id,
      owner_type: "Organization", base_role_id: @maintain_role.id)
    @another_custom_role = create(:custom_repository_role, :with_extra_permissions, owner_id: @organization.id,
      owner_type: "Organization", base_role_id: @maintain_role.id)
    @custom_org_role = create(:custom_organization_role, :with_extra_permissions, owner_id: @organization.id,)
    @another_custom_org_role = create(:custom_organization_role, :with_extra_permissions, owner_id: @organization.id,)
  end

  context "#target" do
    test "raises error when accessing non ActiveRecord target" do
      package_reader = Role.presets.find_by(name: "package_reader")
      user_role = create(:user_role, actor: @user, role: package_reader, target_type: "Package", target_id: 3)

      err = assert_raises(UserRole::UnknownTargetClassError) do
        user_role.target
      end
      assert_equal "Target type `Package` cannot be accessed as an association.", err.message
    end
  end

  context "#org plan support for FGP-based system repo role" do
    %w(business business_plus free).each do |plan|
      test "valid if the target owner is an organization on the #{plan} plan" do
        org = create(:organization, plan: plan)
        repo = create(:repository, :minimal, owner: org)

        user_role = UserRole.new(
          actor: @user,
          target: repo,
          role: @triage_role,
        )
        assert user_role.valid?
      end
    end

    test "invalid if the target owner is an organization on a legacy plan" do
      legacy_org = create(:organization, plan: "neptunium")
      repo = create(:repository, :minimal, owner: legacy_org)

      user_role = UserRole.new(
        actor: @user,
        target: repo,
        role: @triage_role,
      )
      refute user_role.valid?
    end
  end

  test "is destroyed if user actor is destroyed" do
    user_role = UserRole.create(
      actor: @user,
      target: @repo,
      role: @triage_role,
    )
    assert_difference("UserRole.count", -1) do
      @user.destroy
    end
  end

  test "is destroyed if team actor is destroyed" do
    user_role = UserRole.create(
      actor: @team,
      target: @repo,
      role: @triage_role,
    )
    assert_difference("UserRole.count", -1) do
      perform_enqueued_jobs(only: [DestroyTeamDependantsJob]) do
        @team.destroy
      end
    end
  end

  test "does not allow an actor to be assigned multiple roles on the same target_type unless in the exception list " do
    user_role = UserRole.create(
      actor: @user,
      target: @repo,
      role: @triage_role,
    )
    user_role.save

    second_user_role = UserRole.create(
      actor: @user,
      target: @repo,
      role: @maintain_role,
    )

    refute_predicate second_user_role, :valid?
    assert_raises ActiveRecord::RecordInvalid do
      second_user_role.save!
    end
  end

  test "allow an actor to be assigned multiple roles on the same target_type if in the exception list " do
    user_org_role = UserRole.create(
      actor: @user,
      target_id: @organization.id,
      target_type: "Organization",
      role: @custom_org_role,
    )

    second_user_org_role = UserRole.create(
      actor: @user,
      target_id: @organization.id,
      target_type: "Organization",
      role: @another_custom_org_role,
    )

    assert_predicate second_user_org_role, :valid?
    second_user_org_role.save!
  end

  test "does not allow an actor to be assigned the same role twice on a multiple assignment target_type" do
    user_org_role = UserRole.create(
      actor: @user,
      target_id: @organization.id,
      target_type: "Organization",
      role: @custom_org_role,
    )

    second_user_org_role = UserRole.create(
      actor: @user,
      target_id: @organization.id,
      target_type: "Organization",
      role: @custom_org_role,
    )

    refute_predicate second_user_org_role, :valid?
    assert_raises ActiveRecord::RecordInvalid do
      second_user_org_role.save!
    end
  end
end
