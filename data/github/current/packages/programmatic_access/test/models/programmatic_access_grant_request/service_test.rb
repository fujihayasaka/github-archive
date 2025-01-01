# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class ProgrammaticAccessGrantRequest::ServiceTest < GitHub::TestCase
  include PermissionsHelper
  include ApiProgrammaticGrantHelpers

  fixtures do
    @user = create(:user)
    @admin = create(:user)
    @org = create(:organization, admin: @admin)
    @member = create(:user)

    @org.add_member(@member)
    @org.update_default_repository_permission(:none, actor: @admin)

    @access = create(:user_programmatic_access, owner: @member)
    attributes = { permissions: { "members" => :read } }
    @grant_request = create_request(target: @org, access: @access, actor: @member, attributes: attributes)
  end

  context "create" do
    test "creates a request for an organization target" do
      assert_difference("OrganizationProgrammaticAccessGrantRequest.count", 1) do
        pat = create(:user_programmatic_access, owner: @member)
        ProgrammaticAccessGrantRequest::Service.create(access: pat, target: @org, actor: @member, permissions: { "checks" => :write }, repository_selection: :all, repositories: [])
      end

      expected_permissions = {
        "checks"   => :write,
        "metadata" => :read
      }

      grant_request = OrganizationProgrammaticAccessGrantRequest.last!
      assert_equal expected_permissions, grant_request.permissions
      assert_equal [], grant_request.repositories
      assert_equal "all", grant_request.repository_selection
    end

    test "creates a request for a user target" do
      assert_difference("UserProgrammaticAccessGrantRequest.count", 1) do
        pat = create(:user_programmatic_access, owner: @user)
        ProgrammaticAccessGrantRequest::Service.create(access: pat, target: @user, actor: @user, permissions: { "checks" => :write }, repository_selection: :all, repositories: [])
      end

      expected_permissions = {
        "checks"   => :write,
        "metadata" => :read
      }

      grant_request = UserProgrammaticAccessGrantRequest.last
      assert_equal expected_permissions, grant_request.permissions
      assert_equal [], grant_request.repositories
      assert_equal "all", grant_request.repository_selection
    end

    test "instrument creation" do
      pat = create(:user_programmatic_access, owner: @user)
      UserProgrammaticAccessGrantRequest.any_instance.expects(:instrument_creation).once
      request = ProgrammaticAccessGrantRequest::Service.create(access: pat, target: @user, actor: @user, permissions: { "checks" => :write }, repository_selection: :all, repositories: [])

      assert_predicate request, :persisted?
    end

    test "target must be provided" do
      request = ProgrammaticAccessGrantRequest::Service.create(
        access: create(:user_programmatic_access, owner: @user), actor: @user,
        permissions: { "emails" => :read }
      )

      refute_predicate request, :persisted?
      assert_includes request.errors[:target], "must exist"
    end

    test "skip instrumentation on creation failures" do
      UserProgrammaticAccessGrantRequest.any_instance.expects(:instrument_creation).never
      request = ProgrammaticAccessGrantRequest::Service.create(
        access: create(:user_programmatic_access, owner: @user), actor: @user,
        permissions: { "emails" => :read }
      )

      refute_predicate request, :persisted?
    end

    test "access must be provided" do
      request = ProgrammaticAccessGrantRequest::Service.create(
        target: @org, actor: @user,
        permissions: { "emails" => :read }
      )

      refute_predicate request, :persisted?
      assert_includes request.errors[:access], "must exist"
    end

    test "actor must be provided" do
      request = ProgrammaticAccessGrantRequest::Service.create(
        target: @org, access: create(:user_programmatic_access, owner: @user),
        permissions: { "emails" => :read }
      )

      refute_predicate request, :persisted?
      assert_includes request.errors[:actor], "must exist"
    end

    test "repository_selection must be :all, :subset, or :none" do
      request = ProgrammaticAccessGrantRequest::Service.create(
        target: @org, access: create(:user_programmatic_access, owner: @member), actor: @member,
        permissions: { "metadata" => :read },
        repository_selection: :foo
      )

      refute_predicate request, :persisted?
      assert_includes request.errors[:repository_selection], "is not included in the list"
    end

    test "permissions must be from the valid set" do
      request = ProgrammaticAccessGrantRequest::Service.create(
        target: @org, access: create(:user_programmatic_access, owner: @member), actor: @member,
        permissions: { "foo" => :read },
      )

      refute_predicate request, :persisted?
      assert_includes request.errors[:permissions], "'foo' is not a valid permission"
    end

    test "actions must be either :read, :write, or :admin" do
      request = ProgrammaticAccessGrantRequest::Service.create(
        target: @org, access: create(:user_programmatic_access, owner: @member), actor: @member,
        permissions: { "metadata" => :foo },
      )

      refute_predicate request, :persisted?
      assert_includes request.errors[:permissions], "'foo' is not a valid action"
    end

    test "cannot request :read on a write-only permission" do
      request = ProgrammaticAccessGrantRequest::Service.create(
        target: @org, access: create(:user_programmatic_access, owner: @member), actor: @member,
        permissions: { "metadata" => :read, "workflows" => :read },
      )

      refute_predicate request, :persisted?
      assert_includes request.errors[:permissions], "'workflows' is only available as 'write'"
    end

    test "cannot request :write on a read-only permission" do
      request = ProgrammaticAccessGrantRequest::Service.create(
        target: @org, access: create(:user_programmatic_access, owner: @member), actor: @member,
        permissions: { "metadata" => :write },
      )

      refute_predicate request, :persisted?
      assert_includes request.errors[:permissions], "'metadata' is only available as 'read'"
    end

    test "cannot request :admin on a permission where it isn't available" do
      request = ProgrammaticAccessGrantRequest::Service.create(
        target: @org, access: create(:user_programmatic_access, owner: @member), actor: @member,
        permissions: { "metadata" => :admin },
      )

      refute_predicate request, :persisted?
      assert_includes request.errors[:permissions], "'metadata' is not available as 'admin'"
    end

    test "repositories must be selected if selection is :subset" do
      request = ProgrammaticAccessGrantRequest::Service.create(
        target: @org, access: create(:user_programmatic_access, owner: @member), actor: @member,
        repository_selection: :subset,
      )

      refute_predicate request, :persisted?
      assert_includes request.errors[:repositories], "please select at least one"
    end

    test "repositories selection has an upper bound" do
      repo = create(:repository, :minimal, owner: @org)

      request = ProgrammaticAccessGrantRequest::Service.create(
        target: @org, access: create(:user_programmatic_access, owner: @member), actor: @member,
        repository_selection: :subset,
        repositories: ([repo] * 51),
      )

      refute_predicate request, :persisted?
      assert_includes request.errors[:repositories], "please select no more than 50"
    end

    test "all repositories must belong to the target" do
      other_repo = create(:repository, :minimal)

      request = ProgrammaticAccessGrantRequest::Service.create(
        target: @org, access: create(:user_programmatic_access, owner: @member), actor: @member,
        repositories: [other_repo],
        repository_selection: :subset,
      )

      refute_predicate request, :persisted?
      assert_includes request.errors[:repositories], "one or more requested do not belong to the @#{@org} account"
    end

    test "all repositories must be accessible to the user" do
      other_repo = create(:private_repository, :minimal, owner: @org)
      refute other_repo.readable_by?(@member)

      request = ProgrammaticAccessGrantRequest::Service.create(
        target: @org, access: create(:user_programmatic_access, owner: @member), actor: @member,
        repositories: [other_repo],
        repository_selection: :subset,
      )

      refute_predicate request, :persisted?
      assert_includes request.errors[:repositories], "one or more requested are not accessible to you"
    end

    test "no repositories selected are in the middle of being transferred" do
      repo = create(:repository, :minimal, owner: @org)
      other_user = create(:user)

      RepositoryOrchestration.transfer_type.create(repository: repo).update(state: :running)

      request = ProgrammaticAccessGrantRequest::Service.create(
        target: @org, access: create(:user_programmatic_access, owner:  @member), actor: @member,
        repositories: [repo],
        repository_selection: :subset,
      )

      refute_predicate request, :persisted?
      assert_includes request.errors[:repositories], "one or more are in the process of being transferred"
    end

    test "does not grant User permissions if requested for org target" do
      request = ProgrammaticAccessGrantRequest::Service.create(
        target: @org, access: create(:user_programmatic_access, owner:  @member), actor: @member,
        permissions: { "emails" => :read }
      )

      refute_granted_in_permissions_table(
        actor_id: request.ability_id, actor_type: request.ability_type,
        subject_id: @org.ability_id, subject_type: "User/emails", action: :read,
      )
    end

    test "grants repository access to selected repositories" do
      repo = create(:repository, :minimal, owner: @org)

      request = ProgrammaticAccessGrantRequest::Service.create(
        target: @org, access: create(:user_programmatic_access, owner:  @member), actor: @member,
        permissions: { "metadata" => :read },
        repositories: [repo], repository_selection: :subset,
      )

      assert_actor_and_subject_granted_in_permissions_table(
        actor: request, subject: repo.resources.metadata, action: :read
      )
    end

    test "grants access to all repositories" do
      request = ProgrammaticAccessGrantRequest::Service.create(
        target: @org, access: create(:user_programmatic_access, owner:  @member), actor: @member,
        repository_selection: :all,
        permissions: { "metadata" => :read },
      )

      assert_actor_and_subject_granted_in_permissions_table(
        actor: request, subject: @org.repository_resources.metadata, action: :read
      )
    end

    test "creates a request with an existing grant" do
      existing_grant = ProgrammaticAccessGrantRequest::Service.approve(@grant_request, @admin, entry_point: :test_case)
      second_request = create_request(target: @org, access: @access, actor: @member, attributes: { permissions: { "checks" => :write }, repository_selection: :all })

      assert_equal existing_grant, second_request.grant
    end

    test "rollsback if permission creation fails" do
      Permission.expects(:insert_all!).raises(ActiveRecord::RecordInvalid)

      assert_no_difference("OrganizationProgrammaticAccessGrantRequest.count") do
        assert_no_difference("Permission.count") do
          ProgrammaticAccessGrantRequest::Service.create(
            target: @org, access: create(:user_programmatic_access, owner:  @member), actor: @member,
            repository_selection: :all,
            permissions: { "metadata" => :read },
          )
        end
      end
    end

    test "rollsback if the request fails to save" do
      OrganizationProgrammaticAccessGrantRequest.any_instance.expects(:save!).raises(ActiveRecord::RecordInvalid)

      assert_no_difference("OrganizationProgrammaticAccessGrantRequest.count") do
        assert_no_difference("Permission.count") do
          ProgrammaticAccessGrantRequest::Service.create(
            target: @org, access: create(:user_programmatic_access, owner:  @member), actor: @member,
            repository_selection: :all,
            permissions: { "metadata" => :read },
          )
        end
      end
    end

    test "creates a new request for existing token when expiration validation is skipped and FF enabled", feature_enabled: :infinite_fg_pat_lifetime do
      @org.set_fine_grained_personal_access_token_expiration_limit(actor: @admin, expiration: 30)
      pat = create(:user_programmatic_access, owner: @member, expires_at: 30.days.from_now)

      expected_permissions = {
        "checks"   => :write,
        "metadata" => :read
      }

      assert_difference("OrganizationProgrammaticAccessGrantRequest.count", 1) do
        ProgrammaticAccessGrantRequest::Service.create(access: pat, target: @org, actor: @member, permissions: expected_permissions, repository_selection: :all, repositories: [], skip_expiration_validation: true)
      end

      grant_request = OrganizationProgrammaticAccessGrantRequest.last!
      assert_equal expected_permissions, grant_request.permissions
      assert_equal [], grant_request.repositories
      assert_equal "all", grant_request.repository_selection

      ProgrammaticAccessGrantRequest.deny(grant_request, @admin, entry_point: :test_case)
      @org.set_fine_grained_personal_access_token_expiration_limit(actor: @admin, expiration: 7)

      expected_permissions = {
        "checks"   => :write,
        "contents" => :read,
        "metadata" => :read
      }

      result = ProgrammaticAccessGrantRequest::Service.create(access: pat, target: @org, actor: @member, permissions: expected_permissions, repository_selection: :all, repositories: [], skip_expiration_validation: true)

      grant_request = OrganizationProgrammaticAccessGrantRequest.last!
      assert_empty result.errors
      assert_equal expected_permissions, grant_request.permissions
      assert_equal [], grant_request.repositories
      assert_equal "all", grant_request.repository_selection
    end

    test "fails to create a new request for existing token when expiration validation is not skipped and FF enabled", feature_enabled: :infinite_fg_pat_lifetime do
      @org.set_fine_grained_personal_access_token_expiration_limit(actor: @admin, expiration: 30)
      pat = create(:user_programmatic_access, owner: @member, expires_at: 30.days.from_now)

      expected_permissions = {
        "checks"   => :write,
        "metadata" => :read
      }

      assert_difference("OrganizationProgrammaticAccessGrantRequest.count", 1) do
        ProgrammaticAccessGrantRequest::Service.create(access: pat, target: @org, actor: @member, permissions: expected_permissions, repository_selection: :all, repositories: [])
      end

      grant_request = OrganizationProgrammaticAccessGrantRequest.last!
      assert_equal expected_permissions, grant_request.permissions
      assert_equal [], grant_request.repositories
      assert_equal "all", grant_request.repository_selection

      ProgrammaticAccessGrantRequest.deny(grant_request, @admin, entry_point: :test_case)
      @org.set_fine_grained_personal_access_token_expiration_limit(actor: @admin, expiration: 7)

      expected_permissions = {
        "checks"   => :write,
        "contents" => :read,
        "metadata" => :read
      }

      result = ProgrammaticAccessGrantRequest::Service.create(access: pat, target: @org, actor: @member, permissions: expected_permissions, repository_selection: :all, repositories: [], skip_expiration_validation: false)

      refute_empty result.errors
      assert_equal result.errors[:base].first, "#{@org.display_login} does not allow tokens to be created with expiration above 7 days"
    end

    test "creates a new request for existing token when expiration validation is skipped and FF disabled" do
      GitHub.flipper[:infinite_fg_pat_lifetime].disable

      @org.set_fine_grained_personal_access_token_expiration_limit(actor: @admin, expiration: 30)
      pat = create(:user_programmatic_access, owner: @member, expires_at: 30.days.from_now)

      expected_permissions = {
        "checks"   => :write,
        "metadata" => :read
      }

      assert_difference("OrganizationProgrammaticAccessGrantRequest.count", 1) do
        ProgrammaticAccessGrantRequest::Service.create(access: pat, target: @org, actor: @member, permissions: expected_permissions, repository_selection: :all, repositories: [], skip_expiration_validation: true)
      end

      grant_request = OrganizationProgrammaticAccessGrantRequest.last!
      assert_equal expected_permissions, grant_request.permissions
      assert_equal [], grant_request.repositories
      assert_equal "all", grant_request.repository_selection

      ProgrammaticAccessGrantRequest.deny(grant_request, @admin, entry_point: :test_case)
      @org.set_fine_grained_personal_access_token_expiration_limit(actor: @admin, expiration: 7)

      expected_permissions = {
        "checks"   => :write,
        "contents" => :read,
        "metadata" => :read
      }

      result = ProgrammaticAccessGrantRequest::Service.create(access: pat, target: @org, actor: @member, permissions: expected_permissions, repository_selection: :all, repositories: [], skip_expiration_validation: true)

      grant_request = OrganizationProgrammaticAccessGrantRequest.last!
      assert_empty result.errors
      assert_equal expected_permissions, grant_request.permissions
      assert_equal [], grant_request.repositories
      assert_equal "all", grant_request.repository_selection
    end

    test "fails to create a new request for existing token when expiration validation is not skipped and FF disabled" do
      GitHub.flipper[:infinite_fg_pat_lifetime].disable
      GitHub.flipper[:fg_pat_expiration_lifecycle_enforcement].enable
      GitHub.flipper[:personal_access_token_expiration_limit].enable
      @org.set_fine_grained_personal_access_token_expiration_limit(actor: @admin, expiration: 30)
      pat = create(:user_programmatic_access, owner: @member, expires_at: 30.days.from_now)

      expected_permissions = {
        "checks"   => :write,
        "metadata" => :read
      }

      assert_difference("OrganizationProgrammaticAccessGrantRequest.count", 1) do
        ProgrammaticAccessGrantRequest::Service.create(access: pat, target: @org, actor: @member, permissions: expected_permissions, repository_selection: :all, repositories: [])
      end

      grant_request = OrganizationProgrammaticAccessGrantRequest.last!
      assert_equal expected_permissions, grant_request.permissions
      assert_equal [], grant_request.repositories
      assert_equal "all", grant_request.repository_selection

      ProgrammaticAccessGrantRequest.deny(grant_request, @admin, entry_point: :test_case)
      @org.set_fine_grained_personal_access_token_expiration_limit(actor: @admin, expiration: 7)

      expected_permissions = {
        "checks"   => :write,
        "contents" => :read,
        "metadata" => :read
      }

      result = ProgrammaticAccessGrantRequest::Service.create(access: pat, target: @org, actor: @member, permissions: expected_permissions, repository_selection: :all, repositories: [], skip_expiration_validation: false)

      refute_empty result.errors
      assert_equal result.errors[:base].first, "#{@org.display_login} does not allow tokens to be created with expiration above 7 days"
    end
  end

  context "approve" do
    test "creates grant if one doesn't exist" do
      expected_permissions = @grant_request.permissions
      expected_repositories = @grant_request.repositories
      expected_repository_selection = @grant_request.repository_selection

      assert_difference("OrganizationProgrammaticAccessGrant.count", 1) do
        ProgrammaticAccessGrantRequest::Service.approve(@grant_request, @admin, entry_point: :test_case)
      end

      grant = OrganizationProgrammaticAccessGrant.last!
      assert_equal expected_permissions, grant.permissions
      assert_equal expected_repositories, grant.repositories
      assert_equal expected_repository_selection, grant.repository_selection
    end

    test "successfully transfers permission to existing grant" do
      existing_grant = ProgrammaticAccessGrantRequest::Service.approve(@grant_request, @admin, entry_point: :test_case)
      second_request = create_request(target: @org, access: @access, actor: @member, attributes: { permissions: { "checks" => :write }, repository_selection: :all })

      expected_permissions = second_request.permissions
      expected_repositories = second_request.repositories
      expected_repository_selection = second_request.repository_selection

      assert_no_difference("OrganizationProgrammaticAccessGrant.count") do
        ProgrammaticAccessGrantRequest::Service.approve(second_request, @admin, entry_point: :test_case)
      end

      assert_equal expected_permissions, existing_grant.permissions
      assert_equal expected_repositories, existing_grant.repositories
      assert_equal expected_repository_selection, existing_grant.repository_selection
    end

    test "can approve a UserProgrammaticAccessGrantRequest" do
      user_request = create_request(
        target: @user,
        access: create(:user_programmatic_access, owner: @user),
        actor: @user,
        attributes: {}
      )

      assert_difference("UserProgrammaticAccessGrant.count", 1) do
        ProgrammaticAccessGrantRequest::Service.approve(user_request, @user, entry_point: :test_case)
      end
    end

    test "updates permission records instead of rewriting" do
      request_permission_record_ids = Permission.where(actor_id: @grant_request.ability_id, actor_type: @grant_request.ability_type).map(&:id)
      grant = ProgrammaticAccessGrantRequest::Service.approve(@grant_request, @admin, entry_point: :test_case)
      grant_permission_record_ids = Permission.where(actor_id: grant.ability_id, actor_type: grant.ability_type).map(&:id)

      assert_same_elements request_permission_record_ids, grant_permission_record_ids
    end

    test "destroys request upon success" do
      assert_difference("OrganizationProgrammaticAccessGrantRequest.count", -1) do
        perform_enqueued_jobs(only: [ClearAbilitiesJob, DestroyDependentRecordsJob]) do
          ProgrammaticAccessGrantRequest::Service.approve(@grant_request, @admin, entry_point: :test_case)
        end
      end

      assert_equal 0, Permission.where(actor_id: @grant_request.ability_id, actor_type: @grant_request.ability_type).count
    end

    test "actor must be able to approve requests for the target" do
      grant = ProgrammaticAccessGrantRequest::Service.approve(@grant_request, @user, entry_point: :test_case)

      refute_predicate grant, :persisted?
      assert_includes grant.errors[:actor], "must have sufficient permissions to approve this request"
    end

    test "org member can approve their own request if they are asking for less acces" do
      member_pat2 = create(:user_programmatic_access, owner: @member)
      grant_request = create_request(target: @org, access: member_pat2, actor: @member, attributes: {
        permissions: { "members" => :write }
      })

      # Approve the first request as an admin.
      grant = ProgrammaticAccessGrantRequest::Service.approve(grant_request, @admin, entry_point: :test_case)
      assert_predicate grant, :persisted?

      # The @member then decides they only need members => read.
      grant_request2 = create_request(target: @org, access: member_pat2, actor: @member, attributes: {
        permissions: { "members" => :read }
      })

      # The member can approve their own request because we are "downgrading"
      # permissions (write -> read).
      grant2 = ProgrammaticAccessGrantRequest::Service.approve(grant_request2, @member, entry_point: :test_case)
      refute_predicate grant2.errors, :any?

      assert_same_hash({ "members" => :read }, grant2.permissions)
    end

    test "notifies access owner about the approval" do
      UserProgrammaticAccess
        .expects(:notify_owner)
        .with(
          about: :request_approved,
          accesses: [@access],
          owner: @access.owner,
          target: @org,
          reason: nil
        )

      grant = ProgrammaticAccessGrantRequest::Service.approve(@grant_request, @admin, entry_point: :test_case)
      assert_predicate grant, :persisted?
    end

    test "does not notify access owner about the approval on failures" do
      UserProgrammaticAccess.expects(:notify_owner).never

      grant = ProgrammaticAccessGrantRequest::Service.approve(@grant_request, @user, entry_point: :test_case)
      refute_predicate grant, :persisted?
    end

    test "actor must be provided" do
      grant = ProgrammaticAccessGrantRequest::Service.approve(@grant_request, nil, entry_point: :test_case)

      refute_predicate grant, :persisted?
      assert_includes grant.errors[:actor], "must exist"
    end

    test "does not validate repos for repository selection :all" do
      ProgrammaticAccessGrantRequest::Service.any_instance.expects(:all_repositories_belong_to_target).never
      ProgrammaticAccessGrantRequest::Service.any_instance.expects(:no_repository_transfers_in_progress).never
      ProgrammaticAccessGrantRequest::Service.any_instance.expects(:all_repositories_accessible_to_actor).never
      ProgrammaticAccessGrantRequest::Service.any_instance.expects(:repository_ids).never

      create(:repository, owner: @org)
      request = ProgrammaticAccessGrantRequest::Service.create(
        target: @org,
        access: create(:user_programmatic_access, owner: @member),
        actor: @member,
        repository_selection: :all,
        repositories: [],
        permissions: { "metadata" => :read }
      )

      assert_equal :all, request.repository_selection.to_sym
      refute_empty request.repositories

      assert_difference("OrganizationProgrammaticAccessGrant.count", 1) do
        ProgrammaticAccessGrantRequest::Service.approve(request, @admin, entry_point: :test_case)
      end
    end

    test "rollsback if permission update fails" do
      m = mock
      m.expects(:update_all).raises(ActiveRecord::StatementInvalid)
      ActiveRecord::Relation.any_instance.expects(:in_batches).returns(m)

      assert_no_difference("OrganizationProgrammaticAccessGrant.count") do
        assert_no_difference("Permission.count") do
          ProgrammaticAccessGrantRequest::Service.approve(@grant_request, @admin, entry_point: :test_case)
        end
      end
    end

    test "rollsback if the grant fails to save" do
      OrganizationProgrammaticAccessGrant.any_instance.expects(:save!).raises(ActiveRecord::RecordInvalid)

      assert_no_difference("OrganizationProgrammaticAccessGrant.count") do
        assert_no_difference("Permission.count") do
          ProgrammaticAccessGrantRequest::Service.approve(@grant_request, @admin, entry_point: :test_case)
        end
      end
    end

    test "rollsback if request destroy fails" do
      OrganizationProgrammaticAccessGrantRequest.any_instance.expects(:destroy!).raises(ActiveRecord::RecordInvalid)

      assert_no_difference("OrganizationProgrammaticAccessGrant.count") do
        assert_no_difference("Permission.count") do
          assert_no_difference("OrganizationProgrammaticAccessGrantRequest.count") do
            ProgrammaticAccessGrantRequest::Service.approve(@grant_request, @admin, entry_point: :test_case)
          end
        end
      end
    end

    test "instruments access granting on request approval" do
      events = subscribe "personal_access_token.access_granted"

      ProgrammaticAccessGrantRequest::Service.approve(@grant_request, @admin, entry_point: :test_case)

      grant = @access.grant

      expected_payload = {
        user_programmatic_access_id: @access.id,
        user_programmatic_access_name: @access.name,
        organization_programmatic_access_grant_id: grant.id,
        requester: @member.login,
        requester_id: @member.id,
        target: @org.login,
        target_id: @org.id,
        org: @org.login,
        org_id: @org.id,
        repository_selection: grant.repository_selection,
        permissions: grant.permissions,
        token_id: @access.id,
      }

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload, event.payload
    end

    test "instruments granting on request approval when grant record exists" do
      request = @access.grant_request
      refute_predicate request, :grant # Has no existing grant

      ProgrammaticAccessGrantRequest::Service.approve(request, @admin, entry_point: :test_case)

      assert_predicate request, :destroyed?

      # Create new request with existing grant
      new_permissions = { "metadata" => :read }
      grant = @access.grant
      new_request = create_request(
        target: @org,
        access: @access,
        actor: @member,
        attributes: grant.permissions.merge(new_permissions))

      assert_predicate @access, :grant_request
      assert_predicate new_request, :grant # Has existing grant

      events = subscribe "personal_access_token.access_granted"

      # We approve a new request
      ProgrammaticAccessGrantRequest::Service.approve(new_request, @admin, entry_point: :test_case)
      assert_predicate new_request, :destroyed?

      expected_payload = {
        user_programmatic_access_id: @access.id,
        user_programmatic_access_name: @access.name,
        organization_programmatic_access_grant_id: grant.id,
        requester: @member.login,
        requester_id: @member.id,
        target: @org.login,
        target_id: @org.id,
        org: @org.login,
        org_id: @org.id,
        repository_selection: grant.repository_selection,
        permissions: grant.permissions,
        token_id: @access.id,
      }

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload, event.payload
    end

    test "includes business info in the instrumentation payload when present in the org" do
      events = subscribe "personal_access_token.access_granted"

      biz = create(:business)
      biz_org = create(:organization, admin: @admin, business: biz)

      access = create(:user_programmatic_access, owner: @admin)
      expected_permissions = { "members" => :read }
      grant_request = create_request(target: biz_org, access: access, actor: @admin, attributes: { permissions: expected_permissions })

      ProgrammaticAccessGrantRequest::Service.approve(grant_request, @admin, entry_point: :test_case)

      grant = access.grant

      expected_payload = {
        user_programmatic_access_id: access.id,
        user_programmatic_access_name: access.name,
        organization_programmatic_access_grant_id: grant.id,
        requester: @admin.login,
        requester_id: @admin.id,
        target: biz_org.login,
        target_id: biz_org.id,
        org: biz_org.login,
        org_id: biz_org.id,
        business: biz.slug,
        business_id: biz.id,
        repository_selection: grant.repository_selection,
        permissions: expected_permissions,
        token_id: access.id,
      }

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload, event.payload
    end
  end

  context "bulk_approve" do
    test "actor must be able to approve requests for the target" do
      result = ProgrammaticAccessGrantRequest::Service.bulk_approve([@grant_request.id], @user, @org, entry_point: :test_case)

      assert_includes result.errors[:actor], "must have sufficient permissions to approve requests"
    end

    test "actor must be provided" do
      result = ProgrammaticAccessGrantRequest::Service.bulk_approve([@grant_request.id], nil, @org, entry_point: :test_case)

      assert_includes result.errors[:actor], "must exist"
    end

    test "target must be provided" do
      result = ProgrammaticAccessGrantRequest::Service.bulk_approve([@grant_request.id], @admin, nil, entry_point: :test_case)

      assert_includes result.errors[:target], "must exist"
    end

    test "actor must have permission to approve all requests" do
      member = create(:user)
      @org.add_member(member)

      member_pat = create(:user_programmatic_access, owner: member)
      grant_request = ProgrammaticAccessGrantRequest.create({
        access: member_pat, target: @org, actor: member,
        permissions: { "members" => :read },
      })

      assert_predicate grant_request, :persisted?

      grant = ProgrammaticAccessGrantRequest.approve(grant_request, @admin, entry_point: :test_case)
      assert_predicate grant, :persisted?

      # Make another request with more permissions
      grant_request2 = ProgrammaticAccessGrantRequest.create({
        access: member_pat, target: @org, actor: member,
        permissions: { "members" => :read },
      })

      another_member_pat = create(:user_programmatic_access, owner: member)
      another_grant_request = ProgrammaticAccessGrantRequest.create({
        access: another_member_pat, target: @org, actor: member,
        permissions: { "members" => :read },
      })

      assert_predicate another_grant_request, :persisted?

      another_grant = ProgrammaticAccessGrantRequest.approve(another_grant_request, @admin, entry_point: :test_case)
      assert_predicate another_grant, :persisted?

      # Make another request with more permissions
      another_grant_request2 = ProgrammaticAccessGrantRequest.create({
        access: another_member_pat, target: @org, actor: member,
        permissions: { "members" => :write },
      })

      result = ProgrammaticAccessGrantRequest::Service.bulk_approve(
        [grant_request2.id, another_grant_request2.id],
        member,
        @org,
        entry_point: :test_case
      )

      assert_includes result.errors[:actor], "must have sufficient permissions to approve requests"
    end

    test "ignores requests from other targets" do
      owner = create(:user)
      access = create(:user_programmatic_access, owner: owner)
      org = create(:organization)
      org.add_member(owner)

      grant_request = create_request(target: org, access: access, actor: owner, attributes: {})

      perform_enqueued_jobs(only: [BulkApproveProgrammaticAccessGrantRequestsJob]) do
        assert_difference("OrganizationProgrammaticAccessGrantRequest.count", -1) do
          assert_difference("OrganizationProgrammaticAccessGrant.count", 1) do
            ProgrammaticAccessGrantRequest::Service.bulk_approve(
              [@grant_request.id, grant_request.id],
              @admin,
              @org,
              entry_point: :test_case
            )
          end
        end
      end

      assert_predicate grant_request.reload, :persisted?
    end

    test "returns early if there are errors" do
      perform_enqueued_jobs(only: [BulkApproveProgrammaticAccessGrantRequestsJob]) do
        assert_no_difference("OrganizationProgrammaticAccessGrantRequest.count") do
          assert_no_difference("OrganizationProgrammaticAccessGrant.count") do
            result = ProgrammaticAccessGrantRequest::Service.bulk_approve(
              [@grant_request.id],
              nil,
              @org,
              entry_point: :test_case
            )
          end
        end
      end

      refute @grant_request.destroyed?
    end

    test "approves all grants" do
      access = create(:user_programmatic_access, owner: @member)
      grant_request = create_request(target: @org, access: access, actor: @member, attributes: {})

      perform_enqueued_jobs(only: [BulkApproveProgrammaticAccessGrantRequestsJob]) do
        assert_difference("OrganizationProgrammaticAccessGrantRequest.count", -2) do
          assert_difference("OrganizationProgrammaticAccessGrant.count", 2) do
            result = ProgrammaticAccessGrantRequest::Service.bulk_approve(
              [@grant_request.id, grant_request.id],
              @admin,
              @org,
              entry_point: :test_case
            )

            refute result.errors.any?
          end
        end
      end
    end

    test "notifies owner via mailer about approved request" do
      perform_enqueued_jobs(only: [BulkApproveProgrammaticAccessGrantRequestsJob]) do
        args = [[@grant_request.user_programmatic_access], @member, @org]
        assert_performed_email(mailer: "AccountMailer", action: "programmatic_access_approved_notice", args: args) do
          ProgrammaticAccessGrantRequest::Service.bulk_approve(
            [@grant_request.id],
            @admin,
            @org,
            entry_point: :test_case
          )
        end
      end
    end

    test "notifies owner via mailer about approved requests once" do
      perform_enqueued_jobs(only: [BulkApproveProgrammaticAccessGrantRequestsJob]) do
        AccountMailer.expects(:programmatic_access_approved_notice).once.with(
          [@grant_request.user_programmatic_access], @member, @org
        ).returns(stub(deliver_later: nil))

        ProgrammaticAccessGrantRequest::Service.bulk_approve([@grant_request.id], @admin, @org, entry_point: :test_case)
      end
    end

    test "does not set repos for validation when repository selection is :all" do
      repo_in_subset = create(:repository, owner: @org)
      repo_not_in_subset = create(:repository, owner: @org)
      subset_request = ProgrammaticAccessGrantRequest::Service.create(
        target: @org,
        access: create(:user_programmatic_access, owner: @member),
        actor: @member,
        repositories: [repo_in_subset],
        repository_selection: :subset,
        permissions: { "contents" => :write }
      )
      all_repos_request = ProgrammaticAccessGrantRequest::Service.create(
        target: @org,
        access: create(:user_programmatic_access, owner: @member),
        actor: @member,
        repositories: [],
        repository_selection: :subset,
        permissions: { "metadata" => :read }
      )

      result = ProgrammaticAccessGrantRequest::Service.bulk_approve(
        [subset_request.id, all_repos_request.id],
        @admin,
        @org,
        entry_point: :test_case
      )

      refute_includes result.repositories, repo_not_in_subset
      assert_includes result.repositories, repo_in_subset
    end

    test "all repositories must belong to the target" do
      repo = create(:repository, :minimal, owner: @org)
      request = ProgrammaticAccessGrantRequest::Service.create(
        target: @org, access: create(:user_programmatic_access, owner: @member), actor: @member,
        repositories: [repo],
        repository_selection: :subset,
        permissions: { "checks" => :write }
      )

      # Typically repository transfers revoke all Permission records, but to
      # show the race condition we'll stub this out like it never happened.
      repo.stubs(:remove_programmatic_fine_grained_permissions).returns(nil)

      new_owner = create(:organization, admin: @org.admin)
      repo.transfer_ownership_to(new_owner, actor: @org.admin)

      result = ProgrammaticAccessGrantRequest::Service.bulk_approve(
        [@grant_request.id, request.id],
        @admin,
        @org,
        entry_point: :test_case
      )

      assert_includes result.errors[:repositories], "one or more requested do not belong to the @#{@org} account"
    end

    test "no repositories selected are in the middle of being transferred" do
      repo = create(:repository, :minimal, owner: @org)
      request = ProgrammaticAccessGrantRequest::Service.create(
        target: @org, access: create(:user_programmatic_access, owner: @member), actor: @member,
        repositories: [repo],
        repository_selection: :subset,
        permissions: { "checks" => :write }
      )

      new_owner = create(:organization, admin: @org.admin)
      RepositoryOrchestration.transfer_type.create(repository: repo).update(state: :running)

      result = ProgrammaticAccessGrantRequest::Service.bulk_approve(
        [@grant_request.id, request.id],
        @admin,
        @org,
        entry_point: :test_case
      )

      assert_includes result.errors[:repositories], "one or more are in the process of being transferred"
    end

    test "triggers background job for approving" do
      access = create(:user_programmatic_access, owner: @member)
      grant_request = create_request(target: @org, access: access, actor: @member, attributes: {})

      request_ids = [@grant_request.id, grant_request.id].sort
      BulkApproveProgrammaticAccessGrantRequestsJob.expects(:perform_later).with(@org, request_ids, @admin, equals({ entry_point: :test_case }))

      ProgrammaticAccessGrantRequest::Service.bulk_approve(
        [@grant_request.id, grant_request.id],
        @admin,
        @org,
        entry_point: :test_case
      )
    end
  end

  context "deny" do
    test "actor must be able to deny requests for the target" do
      grant_request = ProgrammaticAccessGrantRequest::Service.deny(@grant_request, @user)

      assert grant_request
      assert_predicate grant_request, :persisted?
      assert_includes grant_request.errors[:actor], "must have sufficient permissions to deny this request"
    end

    test "actor must be provided" do
      grant_request = ProgrammaticAccessGrantRequest::Service.deny(@grant_request, nil)

      assert grant_request
      assert_predicate grant_request, :persisted?
      assert_includes grant_request.errors[:actor], "must exist"
    end

    test "destroys request upon success" do
      assert_difference("OrganizationProgrammaticAccessGrantRequest.count", -1) do
        perform_enqueued_jobs(only: [ClearAbilitiesJob, DestroyDependentRecordsJob]) do
          ProgrammaticAccessGrantRequest::Service.deny(@grant_request, @admin)
        end
      end

      assert_equal 0, Permission.where(actor_id: @grant_request.ability_id, actor_type: @grant_request.ability_type).count
    end

    test "notifies access owner about the denial" do
      UserProgrammaticAccess
        .expects(:notify_owner)
        .with(
          about: :request_denied,
          accesses: [@access],
          owner: @access.owner,
          target: @org,
          reason: "because"
        )

      request = ProgrammaticAccessGrantRequest::Service.deny(@grant_request, @admin, "because")
      assert_predicate request.errors, :empty?
    end

    test "does not notify access owner about the denial on failures" do
      UserProgrammaticAccess.expects(:notify_owner).never

      request = ProgrammaticAccessGrantRequest::Service.approve(@grant_request, @user, entry_point: :test_case)
      assert_predicate request.errors, :any?
    end
  end

  context "bulk_deny" do
    test "actor must be able to deny requests for the target" do
      result = ProgrammaticAccessGrantRequest::Service.bulk_deny([@grant_request.id], @user, @org)

      assert_includes result.errors[:actor], "must have sufficient permissions to deny requests"
    end

    test "actor must be provided" do
      result = ProgrammaticAccessGrantRequest::Service.bulk_deny([@grant_request.id], nil, @org)

      assert_includes result.errors[:actor], "must exist"
    end

    test "target must be provided" do
      result = ProgrammaticAccessGrantRequest::Service.bulk_deny([@grant_request.id], @admin, nil)

      assert_includes result.errors[:target], "must exist"
    end

    test "ignores requests from other targets" do
      owner = create(:user)
      access = create(:user_programmatic_access, owner: owner)
      org = create(:organization)
      org.add_member(owner)

      grant_request = create_request(target: org, access: access, actor: owner, attributes: {})

      perform_enqueued_jobs(only: [BulkDenyProgrammaticAccessGrantRequestsJob]) do
        assert_difference("OrganizationProgrammaticAccessGrantRequest.count", -1) do
          ProgrammaticAccessGrantRequest::Service.bulk_deny(
            [@grant_request.id, grant_request.id],
            @admin,
            @org
          )
        end
      end

      assert_predicate grant_request.reload, :persisted?
    end

    test "returns early if there are errors" do
      result = ProgrammaticAccessGrantRequest::Service.bulk_deny(
        [@grant_request.id],
        nil,
        @org
      )

      refute @grant_request.destroyed?
    end

    test "destroys all grants" do
      access = create(:user_programmatic_access, owner: @member)
      grant_request = create_request(target: @org, access: access, actor: @member, attributes: {})

      perform_enqueued_jobs(only: [BulkDenyProgrammaticAccessGrantRequestsJob]) do
        assert_difference("OrganizationProgrammaticAccessGrantRequest.count", -2) do
          result = ProgrammaticAccessGrantRequest::Service.bulk_deny(
            [@grant_request.id, grant_request.id],
            @admin,
            @org
          )

          refute result.errors.any?
        end
      end
    end

    test "notifies each owner via mailer about denied request" do
      member2 = create(:user)
      @org.add_member(member2)
      @org.update_default_repository_permission(:none, actor: @admin)
      access2 = create(:user_programmatic_access, owner: member2)
      attributes = { permissions: { "members" => :read } }
      grant_request2 = create_request(target: @org, access: access2, actor: member2, attributes: attributes)
      deny_reason = "this is a reason for denial"

      # AccountMailer.expects(:programmatic_access_denied_notice).twice
      args1 = [[@grant_request.user_programmatic_access], @member, @org, deny_reason]
      args2 = [[grant_request2.user_programmatic_access], member2, @org, deny_reason]

      assert_performed_email(mailer: "AccountMailer", action: "programmatic_access_denied_notice", args: args1) do
        assert_performed_email(mailer: "AccountMailer", action: "programmatic_access_denied_notice", args: args2) do
          ProgrammaticAccessGrantRequest::Service.bulk_deny(
            [@grant_request.id, grant_request2.id],
            @admin,
            @org,
            deny_reason
          )
        end
      end
    end
  end

  context "cancel" do
    test "actor cannot cancel requests they don't own" do
      grant_request = ProgrammaticAccessGrantRequest::Service.cancel(@grant_request, @user)

      assert grant_request
      assert_predicate grant_request, :persisted?
      assert_includes grant_request.errors[:actor], "must have sufficient permissions to cancel this request"
    end

    test "actor must be provided" do
      grant_request = ProgrammaticAccessGrantRequest::Service.cancel(@grant_request, nil)

      assert grant_request
      assert_predicate grant_request, :persisted?
      assert_includes grant_request.errors[:actor], "must exist"
    end

    test "destroys request upon success" do
      assert_difference("OrganizationProgrammaticAccessGrantRequest.count", -1) do
        perform_enqueued_jobs(only: [ClearAbilitiesJob, DestroyDependentRecordsJob]) do
          ProgrammaticAccessGrantRequest::Service.cancel(@grant_request, @member)
        end
      end

      assert_equal 0, Permission.where(actor_id: @grant_request.ability_id, actor_type: @grant_request.ability_type).count
    end
  end

  context "accessible_repository_ids_on_by" do
    test "actor can see all the repositories if they are requesting themselves" do
      public_repo = create(:repository, :minimal, owner: @user)
      private_repo = create(:private_repository, :minimal, owner: @user)

      accessible_repository_ids = ProgrammaticAccessGrantRequest::Service.accessible_repository_ids_on_by(@user, @user)
      assert_same_elements [public_repo.id, private_repo.id], accessible_repository_ids
    end

    test "actor can see all repositories if they admin the org" do
      public_repo = create(:repository, :minimal, owner: @org)
      private_repo = create(:private_repository, :minimal, owner: @org)

      assert @org.adminable_by?(@admin)

      accessible_repository_ids = ProgrammaticAccessGrantRequest::Service.accessible_repository_ids_on_by(@org, @admin)
      assert_same_elements [public_repo.id, private_repo.id], accessible_repository_ids
    end

    test "actor can see all public repositories belonging to the org" do
      public_repo = create(:repository, :minimal, owner: @org)
      private_repo = create(:private_repository, :minimal, owner: @org)

      refute private_repo.readable_by?(@member)

      accessible_repository_ids = ProgrammaticAccessGrantRequest::Service.accessible_repository_ids_on_by(@org, @member)
      assert_same_elements [public_repo.id], accessible_repository_ids
    end

    test "actor can only see private repositories that have direct access to on the org" do
      public_repo = create(:repository, :minimal, owner: @org)

      private_repo1 = create(:private_repository, :minimal, owner: @org)
      private_repo2 = create(:private_repository, :minimal, owner: @org)

      refute private_repo1.readable_by?(@member)

      private_repo2.add_member(@member)
      assert private_repo2.readable_by?(@member)

      accessible_repository_ids = ProgrammaticAccessGrantRequest::Service.accessible_repository_ids_on_by(@org, @member)
      assert_same_elements [public_repo.id, private_repo2.id], accessible_repository_ids
    end

    test "actor can see internal repositories in the target org" do
      business = create(:business)
      biz_org = create(:enterprise_linked_organization, business: business)
      biz_org.update_default_repository_permission(:none, actor: @admin)

      public_repo = create(:repository, :minimal, owner: biz_org)
      internal_repo = create(:internal_repository, owner: biz_org)

      biz_org.add_member(@member, action: :read)
      assert internal_repo.readable_by?(@member)

      accessible_repository_ids = ProgrammaticAccessGrantRequest::Service.accessible_repository_ids_on_by(biz_org, @member)
      assert_same_elements [public_repo.id, internal_repo.id], accessible_repository_ids
    end

    test "actor cannot access repositories in another user, for now" do
      other_user = create(:user)
      public_repo = create(:repository, :minimal, owner: other_user)
      private_repo = create(:private_repository, :minimal, owner: other_user)

      accessible_repository_ids = ProgrammaticAccessGrantRequest::Service.accessible_repository_ids_on_by(other_user, @admin)
      assert_equal [], accessible_repository_ids
    end
  end

  context "enforces expiration limits" do
    test "enforces EMU biz expiration limit on user target", feature_enabled: :infinite_fg_pat_lifetime do
      biz = @member.enterprise_managed_business
      biz.set_fine_grained_personal_access_token_expiration_limit(actor: biz.admins.first, expiration: 30)

      request = ProgrammaticAccessGrantRequest::Service.create(
        target: @member, actor: @member, access: create(:user_programmatic_access, owner: @member, expires_at: 1.year.from_now),
        permissions: { "emails" => :read }
      )

      refute_predicate request, :persisted?
      assert_includes request.errors[:base], "#{biz.display_login} does not allow tokens to be created with expiration above 30 days"
    end

    test "enforces EMU biz expiration limit on org target", feature_enabled: :infinite_fg_pat_lifetime do
      biz = @member.enterprise_managed_business
      biz.set_fine_grained_personal_access_token_expiration_limit(actor: biz.admins.first, expiration: 30)

      request = ProgrammaticAccessGrantRequest::Service.create(
        target: @org, actor: @member, access: create(:user_programmatic_access, owner: @member, expires_at: 1.year.from_now),
        permissions: { "emails" => :read }
      )

      refute_predicate request, :persisted?
      assert_includes request.errors[:base], "#{@org.display_login} does not allow tokens to be created with expiration above 30 days"
    end
  end if GitHub.multi_tenant_enterprise?

  def create_request(target:, access:, actor:, attributes:)
    ProgrammaticAccessGrantRequest::Service.create(
      target: target,
      access: access,
      actor: actor,
      repository_selection: attributes[:repository_selection],
      permissions: attributes[:permissions],
      repositories: attributes[:repositories],
      request_reason: attributes[:request_reason],
    )
  end
end
