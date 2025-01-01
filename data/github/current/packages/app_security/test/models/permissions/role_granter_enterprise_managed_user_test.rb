# typed: true
# frozen_string_literal: true

require "test_helper"

class PermissionsGrantersRoleGranterEmuTest < GitHub::TestCase
  unless GitHub.single_business_environment?
    fixtures do
      @user = create(:user)
      @org = create(:business_plus_organization)
      @repo = create(:private_repository, :minimal, owner: @org)
      @org.add_member(@user)
      @org.add_member(@user, action: :admin)

      @read   = Role.read_role
      @triage = Role.triage_role

      @emu = create :emu
      @emu_org = create :enterprise_linked_organization,
                  business: @emu.enterprise_managed_business,
                  admin: @emu
      @emu_repo = create(:private_repository, :minimal, owner: @emu_org)

      @alt_biz_emu = create :emu
    end

    setup do
      @org_package = PackageRegistry::Package.new(OpenStruct.new(
        author_id: @user.id,
        ecosystem: :CONTAINER,
        id: 3,
        namespace: @org.login,
        name: "foo",
      ))

      @emu_org_package = PackageRegistry::Package.new(OpenStruct.new(
        author_id: @emu.id,
        ecosystem: :CONTAINER,
        id: 3,
        namespace: @emu_org.login,
        name: "foo",
      ))

      @actor_lookup = {
        emu: @emu,
        user: @user,
        alt_biz_emu: @alt_biz_emu
      }

      @target_org_lookup = {
        org: @org,
        emu_org: @emu_org
      }

      @target_repo_lookup = {
        repo: @repo,
        emu_repo: @emu_repo
      }

      @role_name_lookup = {
        triage: @triage,
        maintain: Role.maintain_role,
        codespace_role: Role.codespace_org_creator_role,
        package_reader: Role.package_reader_role
      }
    end

    actor_matrix = {
      "grant! an EMU with non enterprise managed targets raises" => [:emu, :org, :repo, :failure],
      "grant! an non-EMU actor with an enterprise managed target raises" => [:user, :emu_org, :emu_repo, :failure],
      "grant! an EMU to a different managed enterprise raises" => [:alt_biz_emu, :emu_org, :emu_repo, :failure],
      "grant! an EMU in the matching Managed Enterprise" => [:emu, :emu_org, :emu_repo, :success]
    }


    target_matrix = {
      "for system roles on a repo target" => [:repo, :maintain],
      "for internal roles with an Org target" => [:org, :codespace_role],
      "for custom roles with an Org target" => [:org, :custom_org_role],
      "for internal roles with a Package target" => [:org_package, :package_reader],
      "for custom roles with a Repository target" => [:repo, :custom_repo_role]
    }

    actor_matrix.each do |actor_test, (actor_ref, target_org_ref, target_repo_ref, expected_result)|
      target_matrix.each do |target_test, (target_type, role_name_ref)|
        test "matrix #{actor_test} #{target_test}" do
          actor = @actor_lookup[actor_ref]
          target_org = @target_org_lookup[target_org_ref]
          target_repo = @target_repo_lookup[target_repo_ref]
          role =
            if role_name_ref == :custom_repo_role
              create(:custom_repository_role, :with_extra_permissions, owner_id: target_org.id, owner_type: "Organization", base_role_id: @read.id)
            elsif role_name_ref == :custom_org_role
              create(:custom_organization_role, owner_id: target_org.id, owner_type: "Organization")
            else
              @role_name_lookup[role_name_ref]
            end


          target =
            case target_type
            when :org
              target_org
            when :repo
              target_repo
            when :org_package
              target_org == @org ? @org_package : @emu_org_package
            end

          refute_predicate actor, :nil?
          refute_predicate target_org, :nil?
          refute_predicate target_repo, :nil?
          refute_predicate role, :nil?

          if expected_result == :failure
            assert_no_difference("Ability.count") do
              assert_no_difference("UserRole.count") do
                assert_raises(::Permissions::Granters::RoleGranter::GrantFailure) do
                  Permissions::Granters::RoleGranter.new(actor: actor, target: target, role: role).grant!
                end
              end
            end
          else
            assert_difference("UserRole.count", 1) do
              result = Permissions::Granters::RoleGranter.new(actor: actor, target: target, role: role).grant!
              assert_predicate result, :success?
            end
          end
        end
      end
    end

    context "subject's target for conditional access" do
      test "must be defined" do
        target_undefined_tfca = Struct.new(:user_role_target_type, :owner, :id, :ability_delegate).new("Repository", @org, @repo.id)

        assert_no_difference("Ability.count") do
          assert_no_difference("UserRole.count") do
            assert_raises ::Permissions::Participant::PermissionTFCARequiredError do
              Permissions::Granters::RoleGranter.new(actor: @user, target: target_undefined_tfca, role: @triage).grant!
            end
          end
        end
      end

      test "can't be :no_target_for_conditional_access" do
        target_with_no_tfca = Struct.new(:user_role_target_type, :owner, :target_for_conditional_access, :id, :ability_delegate).
          new("Repository", @org, :no_target_for_conditional_access, 1, self)

        assert_no_difference("Ability.count") do
          assert_no_difference("UserRole.count") do
            assert_raises ::Permissions::Participant::PermissionTFCARequiredError do
              Permissions::Granters::RoleGranter.new(actor: @user, target: target_with_no_tfca, role: @triage).grant!
            end
          end
        end
      end
    end
  end
end
