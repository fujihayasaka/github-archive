# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/api_programmatic_grant_helpers"
require "test_helpers/abstract_interface_test_helpers"
require "apps/k_v"

class UserProgrammaticAccessTest < GitHub::TestCase
  include ApiProgrammaticGrantHelpers
  include HydroTestHelpers
  include AbstractInterfaceTestHelpers

  fixtures do
    @user = create(:user)
    @org  = create(:organization, admin: @user)

    @repo = create(:repository, :minimal, owner: @user)
    @permissions = { "metadata" => :read, "issues" => :write, "contents" => :read }

    result = ProgrammaticAccess.create_with_grant_and_token(
      actor: @user,
      target: @user,
      access_token_attributes: { name: "First Name", default_expires_at: "7", description: "First description" },
      permissions: @permissions,
      repositories: [@repo],
      repository_selection: :subset,
      entry_point: :test_case
    )

    assert_predicate result.errors, :none?
    @access = result.access
    @grant = result.grantable
  end

  context "validations" do
    test "requires an owner" do
      @access.update(owner: nil)

      refute_predicate @access, :valid?
      assert_includes @access.errors[:owner], "must exist"
    end

    test "requires a bot" do
      @access.update(bot: nil)

      refute_predicate @access, :valid?
      assert_includes @access.errors[:bot], "must exist"
    end

    test "limit on the number of PATs a user can own" do
      UserProgrammaticAccess.stub_const(:MAX_LIMIT, 1) do
        access = build(:user_programmatic_access, owner: @user)
        access.save

        refute_predicate access, :valid?
        assert_includes access.errors[:owner], "cannot have more than 1 token"
      end
    end

    context "#description" do
      test "can be nil" do
        @access.update(description: nil)
        assert_predicate @access, :valid?
      end

      test "it coerces empty string to nil" do
        @access.update(description: "")

        assert_predicate @access, :valid?
        assert_nil @access.description
      end

      test "can be exactly 1024 characters" do
        @access.update(description: ("a" * 1024))

        assert_predicate @access, :valid?
      end

      test "cannot be more than 1024 characters" do
        @access.update(description: ("a" * 1025))

        refute_predicate @access, :valid?
        assert_includes @access.errors[:description], "is too long (maximum is 1024 characters)"
      end

      test "enforces unicode3 if provided" do
        @access.update(description: "Everyone likes 🍿")

        refute_predicate @access, :valid?
        assert_includes @access.errors[:description], "doesn't accept 4-byte Unicode"
      end

      test "cannot include the PATs V2 token prefix (github_pat_)" do
        @access.update(description: "omg my github_pat_2123")

        refute_predicate @access, :valid?
        assert_includes @access.errors[:description], "can't include GitHub token prefix"

        @access.update(description: "github_pat_")
        refute_predicate @access, :valid?
        assert_includes @access.errors[:description], "can't include GitHub token prefix"

        @access.update(description: "myh description\n\ngithub_pat_123")
        refute_predicate @access, :valid?
        assert_includes @access.errors[:description], "can't include GitHub token prefix"
      end
    end

    context "#name" do
      test "must be present" do
        @access.update(name: nil)

        refute_predicate @access, :valid?
        assert_includes @access.errors[:name], "can't be blank"
      end

      test "can have a length up to 40 characters" do
        @access.update(name: ("a" * 41))

        refute_predicate @access, :valid?
        assert_includes @access.errors[:name], "is too long (maximum is 40 characters)"
      end

      test "cannot be named the same as another access owned by the same user" do
        pat_2 = build(:user_programmatic_access, owner: @access.owner, name: @access.name)

        refute_predicate pat_2, :valid?
        assert_includes pat_2.errors[:name], "has already been taken"
      end

      test "can be named the same as another user's access" do
        pat_2 = build(:user_programmatic_access, name: @access.name)
        assert_predicate pat_2, :valid?
      end

      test "enforces unicode3" do
        @access.update(name: "🍿 pat")

        refute_predicate @access, :valid?
        assert_includes @access.errors[:name], "doesn't accept 4-byte Unicode"
      end

      test "cannot include the PATs V2 token prefix (github_pat_)" do
        @access.update(name: "github_pat_foo")

        refute_predicate @access, :valid?
        assert_includes @access.errors[:name], "can't include GitHub token prefix"

        # test it ignores leading whitespaces
        @access.update(name: "   github_pat_bar")
        refute_predicate @access, :valid?
        assert_includes @access.errors[:name], "can't include GitHub token prefix"

        @access.update(name: ".github_pat_bar")
        refute_predicate @access, :valid?
        assert_includes @access.errors[:name], "can't include GitHub token prefix"
      end
    end
  end

  context "callbacks" do
    test "sets previous permissions before updating" do
      assert_predicate @access.previous_permissions, :empty?
      @access.save!
      assert_equal(@permissions, @access.previous_permissions)
    end

    test "sets previous permissions as an empty hash before updating without a grant" do
      @access.grant.destroy!
      assert_predicate @access.previous_permissions, :empty?
      @access.save!
      assert_equal({}, @access.previous_permissions)
    end

    test "saves the pat name in cache before destroy" do
      cache_key = "user_programmatic_access_name_#{@access.id}"
      assert_nil Apps::KV.store.get(cache_key).value!
      @access.destroy!

      expected_hash = {
        "name" => @access.name,
        "owner_id" => @user.id,
        "owner_name" => @user.login,
      }

      actual_hash = JSON.parse Apps::KV.store.get(cache_key).value!

      assert_same_hash expected_hash, actual_hash
    end
  end

  context "#bot" do
    test "generates a new ProgrammaticAccessBot on create" do
      assert_difference "ProgrammaticAccessBot.count", 1 do
        UserProgrammaticAccess.create!(owner: create(:user), name: "pat-#{SecureRandom.hex(8)}")
      end
    end

    test "deletes the ProgrammaticAccessBot asynchronously on destroy" do
      bot = @access.bot

      assert_enqueued_with job: UserDeleteJob, args: [bot.id, bot.login] do
        assert @access.destroy
      end
    end

    test "deleting the ProgrammaticAccessBot doesn't raise exceptions" do
      perform_enqueued_jobs(only: [UserDeleteJob]) do
        @access.destroy!
        assert_predicate @access.bot, :deleted?
      end
    end
  end

  context "#grant" do
    test "returns a user grant when present" do
      access = create(:user_programmatic_access, owner: @user)
      grant  = make_programmatic_access_grant(access: access, target: @user)

      assert_equal grant, access.grant
    end

    test "returns an org grant when present" do
      access = create(:user_programmatic_access, owner: @user)
      grant  = make_programmatic_access_grant(access: access, target: @org)

      assert_equal grant, access.grant
    end

    test "returns the user grant when both are available" do
      access = create(:user_programmatic_access, owner: @user)

      _org_grant = make_programmatic_access_grant(access: access, target: @org)
      user_grant = make_programmatic_access_grant(access: access, target: @user)

      assert_equal user_grant, access.grant
    end
  end

  context "#grant_for" do
    test "returns a grant for the given target if it's present" do
      assert_equal @grant, @access.grant_for(@user)
    end

    test "returns a grant for the given org target if it's present" do
      grant = make_programmatic_access_grant(access: @access, target: @org, actor: @user)
      assert_equal grant, @access.grant_for(@org)
    end

    test "returns nil if a grant for the given target doesn't exist" do
      user = create(:user)
      assert_nil @access.grant_for(user)
    end

    test "can return organization grants" do
      org = create(:organization)
      org.add_admin(@user)

      grant = make_programmatic_access_grant(
        access: @access,
        target: org,
        permissions: { "members" => :read }
      )

      assert_equal grant, @access.grant_for(org)
    end
  end

  context "#grant_for_repository" do
    test "returns nil without a repo" do
      assert_nil @access.grant_for_repository(nil)
    end

    test "does not find grants related to other accesses" do
      repo = create(:repository, :minimal, owner: @user)

      other_access_grant = make_programmatic_access_grant(
        access: create(:user_programmatic_access, owner: @user),
        target: @user,
        permissions: { "metadata" => :read },
        repositories: [repo]
      )

      assert_nil @access.grant_for_repository(repo)
    end

    test "find grants for the given repo" do
      assert_equal @grant, @access.grant_for_repository(@repo)
    end

    test "find grants for the given org owned repo" do
      repo = create(:repository, :minimal, owner: @org)

      grant = make_programmatic_access_grant(
        access: @access, target: @org,
        permissions: { "metadata" => :read },
        repositories: [repo]
      )

      assert_equal grant, @access.grant_for_repository(repo)
    end
  end

  context "#has_requested_grant?" do
    test "is false without a grant request" do
      blank_access = create(:user_programmatic_access, owner: @user)

      assert_nil blank_access.grant
      refute_predicate blank_access, :has_requested_grant?
    end

    test "is false when targeting a user" do
      refute_predicate @access, :has_requested_grant?
    end

    test "is false when org grant has no associated request" do
      access = create(:user_programmatic_access, :org_grants)
      org_grant = access.grant

      assert_nil org_grant.request
      refute_predicate access, :has_requested_grant?
    end

    test "is true when there is an an associated request" do
      access = create(:user_programmatic_access)

      target = create(:organization)
      target.add_member(access.owner)

      grant_request = OrganizationProgrammaticAccessGrantRequest.create(
        target: target, user_programmatic_access: access, actor: access.owner
      )

      assert_predicate grant_request, :persisted?
      assert_predicate access, :has_requested_grant?
    end
  end

  context "#active_request_or_grant" do
    test "is nil without a grant" do
      access = create(:user_programmatic_access, owner: @user)
      assert_nil access.grant
      assert_nil access.active_request_or_grant
    end

    test "it returns the request when there is one" do
      member = create(:user)
      @org.add_member(member)

      access = make_user_programmatic_access_with_grant_request(
        target: @org, actor: member, permissions: { "members" => :read }
      )

      request = access.grant_request
      assert_equal request, access.active_request_or_grant
    end

    test "it returns the organization grant without a request" do
      access = make_user_programmatic_access_with_grant(
        target: @org, requester: @user, permissions: { "members" => :read }
      )

      org_grant = access.grant
      assert_equal org_grant, access.active_request_or_grant
    end

    test "it returns the user grant" do
      access = make_user_programmatic_access_with_grant(
        requester: @user, permissions: { "emails" => :read }
      )

      grant = access.grant
      assert_equal grant, access.active_request_or_grant
    end
  end

  context "instrumentation" do
    test "instruments creation with token and grant" do
      events = subscribe "personal_access_token.create"

      user = create :user
      repo = create(:repository, :minimal, owner: user)
      access = create :user_programmatic_access, owner: user, name: "My PAT"

      requested_permissions = { "issues" => :read, "contents" => :write, "metadata" => :read }
      grant = make_programmatic_access_grant(
        access: access,
        target: user,
        permissions: requested_permissions,
        repositories: [repo],
      )

      expected_token_result = stub_interface(ProgrammaticAccessTokens::IResult, { success?: true, value: "github_pat_token_with_12345678" })

      access.instrument_creation(expected_token_result)

      expected_payload = {
        user_programmatic_access_id: access.id,
        user_programmatic_access_name: access.name,
        user: user.login,
        user_id: user.id,
        token_last_eight: "12345678",
        user_programmatic_access_grant_id: grant.id,
        repository_selection: "subset",
        repository_count: 1,
        hashed_token: "git20P7c6jGcNK4xHnFJWMf+zsLYj63NlCezohKt2No=",
        programmatic_access_type: "Fine-grained personal access token",
        token_id: access.id,
      }

      assert event = events.pop, "an event was expected"
      event_permisions = event.payload.delete(:permissions_added)
      assert_predicate event_permisions, :present?
      assert_equal requested_permissions.sort, event_permisions.sort
      assert_same_hash expected_payload, event.payload
    end

    test "instruments creation without token or a valid grant" do
      events = subscribe "personal_access_token.create"

      user = create :user
      access = create :user_programmatic_access, owner: user, name: "My PAT"
      expected_token_result = stub_interface(ProgrammaticAccessTokens::IResult, { success?: false, value: nil })

      access.instrument_creation(expected_token_result)

      expected_payload = {
        token_id: access.id,
        user_programmatic_access_id: access.id,
        user_programmatic_access_name: access.name,
        user: user.login,
        user_id: user.id,
      }

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload, event.payload
    end

    test "instruments creation doesn't include repos count when granting on all repos" do
      events = subscribe "personal_access_token.create"

      user = create :user
      access = create :user_programmatic_access, owner: user, name: "My PAT"

      requested_permissions = { "issues" => :read, "contents" => :write, "metadata" => :read }
      grant = make_programmatic_access_grant(
        access: access,
        target: user,
        permissions: requested_permissions,
        repository_selection: :all,
      )

      expected_token_result = stub_interface(ProgrammaticAccessTokens::IResult, { success?: true, value: "a_token_with_12345678" })

      access.instrument_creation(expected_token_result)

      expected_payload = {
        user_programmatic_access_id: access.id,
        user_programmatic_access_name: access.name,
        user: user.login,
        user_id: user.id,
        token_last_eight: "12345678",
        user_programmatic_access_grant_id: grant.id,
        repository_selection: "all",
        hashed_token: "UoTK+jVh16R+dL9C4muMDXuWpQlYexIkJbKgrS+D7q8=",
        programmatic_access_type: "OAuth access token created before 2021-04-05",
        token_id: access.id,
      }

      assert event = events.pop, "an event was expected"
      event_permisions = event.payload.delete(:permissions_added)
      assert_predicate event_permisions, :present?
      assert_equal requested_permissions.sort, event_permisions.sort
      assert_same_hash expected_payload, event.payload
    end

    test "instrument creation on an org the user can admin" do
      events = subscribe "personal_access_token.create"

      access = create(:user_programmatic_access, owner: @user)
      requested_permissions = { "metadata" => :read }

      grant = make_programmatic_access_grant(
        access: access, target: @org, permissions: requested_permissions, repository_selection: :all
      )

      expected_token_result = stub_interface(ProgrammaticAccessTokens::IResult, { success?: true, value: "a_token_with_12345678" })

      access.instrument_creation(expected_token_result)

      expected_payload = {
        user_programmatic_access_id: access.id,
        user_programmatic_access_name: access.name,
        user: @user.login,
        user_id: @user.id,
        token_last_eight: "12345678",
        organization_programmatic_access_grant_id: grant.id,
        repository_selection: "all",
        permissions_added: { "metadata" => :read },
        org: @org.login,
        org_id: @org.id,
        hashed_token: "UoTK+jVh16R+dL9C4muMDXuWpQlYexIkJbKgrS+D7q8=",
        programmatic_access_type: "OAuth access token created before 2021-04-05",
        token_id: access.id,
      }

      assert event = events.pop, "an event was expected"
      event_permissions = event.payload[:permissions_added]

      assert_predicate event_permissions, :present?
      assert_same_hash requested_permissions, event_permissions

      assert_same_hash expected_payload, event.payload
    end

    test "instrument creation as an org member" do
      events = subscribe "personal_access_token.create"

      user = create(:user)
      @org.add_member(user)

      access = create(:user_programmatic_access, owner: user)
      requested_permissions = { "metadata" => :read }

      grant_request = make_programmatic_access_grant_request(
        access: access, target: @org, permissions: requested_permissions, repository_selection: :all
      )

      expected_token_result = stub_interface(ProgrammaticAccessTokens::IResult, { success?: true, value: "a_token_with_12345678" })

      access.instrument_creation(expected_token_result)

      expected_payload = {
        user_programmatic_access_id: access.id,
        user_programmatic_access_name: access.name,
        user: user.login,
        user_id: user.id,
        token_last_eight: "12345678",
        organization_programmatic_access_grant_request_id: grant_request.id,
        repository_selection: "all",
        permissions_requested: { "metadata" => :read },
        org: @org.login,
        org_id: @org.id,
        access_requested: true,
        reason: nil,
        hashed_token: "UoTK+jVh16R+dL9C4muMDXuWpQlYexIkJbKgrS+D7q8=",
        programmatic_access_type: "OAuth access token created before 2021-04-05",
        token_id: access.id,
      }

      assert event = events.pop, "an event was expected"
      event_permissions = event.payload[:permissions_requested]

      assert_predicate event_permissions, :present?
      assert_same_hash requested_permissions, event_permissions

      assert_same_hash expected_payload, event.payload
    end

    test "instruments update when name changes" do
      events = subscribe "personal_access_token.update"

      @access.update!(name: "New Name")
      @access.instrument_update

      expected_payload = {
        user_programmatic_access_id: @access.id,
        user_programmatic_access_name: @access.name,
        user: @user.login,
        user_id: @user.id,
        pat_field_changed: "name",
        permissions_unchanged: @permissions,
        user_programmatic_access_grant_id: @access.grant.id,
        repository_selection: "subset",
        repository_count: 1,
        token_id: @access.id,
      }

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload, event.payload
    end

    test "instruments update with multiple changes" do
      events = subscribe "personal_access_token.update"

      @access.update!(name: "New Name", description: "New description now")
      @access.instrument_update

      expected_payload = {
        user_programmatic_access_id: @access.id,
        user_programmatic_access_name: @access.name,
        user: @user.login,
        user_id: @user.id,
        pat_field_changed: "name and description",
        permissions_unchanged: @permissions,
        user_programmatic_access_grant_id: @access.grant.id,
        repository_selection: "subset",
        repository_count: 1,
        token_id: @access.id,
      }

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload, event.payload
    end

    test "instruments regeneration" do
      events = subscribe "personal_access_token.credential_regenerated"

      expected_token_result = stub_interface(ProgrammaticAccessTokens::IResult, { success?: true, value: "a_token_with_12345678" })
      @access.instrument_regeneration(expected_token_result)

      expected_payload = {
        user_programmatic_access_id: @access.id,
        user_programmatic_access_name: @access.name,
        user: @user.login,
        user_id: @user.id,
        token_last_eight: "12345678",
        token_id: @access.id,
      }

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload, event.payload
    end

    test "instruments delete on destroy with explanation" do
      events = subscribe "personal_access_token.destroy"

      grant_id = @access.grant.id
      @access.destroy_with_explanation(:stale)

      expected_payload = {
        user_programmatic_access_id: @access.id,
        user_programmatic_access_name: @access.name,
        user: @user.login,
        user_id: @user.id,
        explanation: :stale,
        user_programmatic_access_grant_id: grant_id,
        token_id: @access.id,
      }

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload, event.payload
    end

    test "instruments delete on destroy without explanation" do
      events = subscribe "personal_access_token.destroy"

      grant_id = @access.grant.id
      @access.destroy

      expected_payload = {
        user_programmatic_access_id: @access.id,
        user_programmatic_access_name: @access.name,
        user: @user.login,
        user_id: @user.id,
        explanation: nil,
        user_programmatic_access_grant_id: grant_id,
        token_id: @access.id,
      }

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload, event.payload
    end

    test "notifies owner via mailer about access created" do
      access = create(:user_programmatic_access, owner: @user)
      AccountMailer
        .expects(:programmatic_access_created_notice)
        .with(access)
        .returns(stub(deliver_later: true))
        .once

      access.notify_owner(about: :created)
    end

    test "notifies owner via mailer about access regenerated" do
      access = create(:user_programmatic_access, owner: @user)
      AccountMailer
        .expects(:programmatic_access_regenerated_notice)
        .with(access)
        .returns(stub(deliver_later: true))
        .once

      assert_equal :ok, access.notify_owner(about: :regenerated)
    end

    test "notifies owner via mailer about access is about to expire" do
      access = create(:user_programmatic_access, owner: @user)
      AccountMailer
        .expects(:programmatic_access_expiration_warning_notice)
        .with(access, "7d")
        .returns(stub(deliver_later: true))
        .once

      assert_equal :ok, access.notify_owner(about: :expiration_warning, details: "7d")
    end

    test "notifies owner via mailer about access has expired" do
      access = create(:user_programmatic_access, owner: @user)
      AccountMailer
        .expects(:programmatic_access_expired_notice)
        .with(access)
        .returns(stub(deliver_later: true))
        .once

      assert_equal :ok, access.notify_owner(about: :expired)
    end

    test "notifies owner via mailer about access revoked" do
      access = make_user_programmatic_access_with_grant(requester: @user, target: @org)

      AccountMailer
        .expects(:programmatic_access_revoked_notice)
        .with([access], @user, @org)
        .returns(stub(deliver_later: true))
        .once

      assert_equal :ok, UserProgrammaticAccess.notify_owner(about: :revoked, accesses: [access], owner: @user, target: @org)
    end

    test "notifies owner via mailer about request approved" do
      access = make_user_programmatic_access_with_grant_request(actor: @user, target: @org)

      AccountMailer
        .expects(:programmatic_access_approved_notice)
        .with([access], @user, @org)
        .returns(stub(deliver_later: true))
        .once

      assert_equal :ok, UserProgrammaticAccess.notify_owner(about: :request_approved, accesses: [access], owner: @user, target: @org)
    end

    test "notifies owner via mailer about request denied" do
      access = make_user_programmatic_access_with_grant_request(actor: @user, target: @org)

      AccountMailer
        .expects(:programmatic_access_denied_notice)
        .with([access], @user, @org, "because")
        .returns(stub(deliver_later: true))
        .once

      assert_equal :ok, UserProgrammaticAccess.notify_owner(about: :request_denied, accesses: [access], owner: @user, target: @org, reason: "because")
    end

    test "skips notification to owner if it was recently sent" do
      access = create(:user_programmatic_access, owner: @user)
      AccountMailer
        .expects(:programmatic_access_created_notice)
        .with(access)
        .returns(stub(deliver_later: true))
        .once

      assert_equal :ok, access.notify_owner(about: :created) # first time it notifies
      assert_nil access.notify_owner(about: :created) # second time is skipped
    end

    if GitHub.guard_audit_log_staff_actor?
      test "instruments delete on destroy and masks the staff actor" do
        events = subscribe "personal_access_token.destroy"

        employee = create(:staff_admin_user)
        GitHub.context.push(actor_id: employee.id)
        grant_id = @access.grant.id
        @access.destroy

        expected_payload = {
          user_programmatic_access_id: @access.id,
          user_programmatic_access_name: @access.name,
          user: @user.login,
          user_id: @user.id,
          actor: User.staff_user.login,
          actor_id: User.staff_user.id,
          staff_actor: employee.login,
          staff_actor_id: employee.id,
          explanation: nil,
          user_programmatic_access_grant_id: grant_id,
          token_id: @access.id,
        }

        assert event = events.pop, "an event was expected"
        assert_same_hash expected_payload, event.payload
      end
    end
  end

  context "publishes to hydro" do
    test "on UserProgrammaticAccess create" do
      disable_cache_storage
      GitHub.stubs(:hydro_enabled?).returns(true)

      Timecop.freeze(Time.now) do
        access = ProgrammaticAccess.new_access(@user, {
          name: "token name"
        })
        access.set_expiration("7", nil)
        access.save!
        make_programmatic_access_grant(
          access: access,
          target: @user,
          permissions: { "metadata" => :read },
          repositories: [@repo],
        )

        expected_token_result = stub_interface(ProgrammaticAccessTokens::IResult, { success?: true, value: "a_token_with_12345678" })
        access.instrument_creation(expected_token_result)

        expiry_time = (Time.zone.now + 7.days).to_i

        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(@user),
          database_id: access.id,
          expires_at_timestamp: expiry_time,
          expires_at_preset: :SEVEN_DAYS
        }
        assert_hydro_published(message, schema: "github.v1.UserProgrammaticAccessCreate")
      end
    end

    test "on UserProgrammaticAccess regenerate" do
      disable_cache_storage
      GitHub.stubs(:hydro_enabled?).returns(true)

      Timecop.freeze(Time.now) do
        expiry_time = (Time.zone.now + 7.days).to_i
        @access.set_expiration("7", nil)
        @access.save!

        expected_token_result = stub_interface(ProgrammaticAccessTokens::IResult, { success?: true, value: "a_token_with_12345678" })
        @access.instrument_regeneration(expected_token_result)

        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(@user),
          database_id: @access.id,
          expires_at_timestamp: expiry_time,
          expires_at_preset: :SEVEN_DAYS
        }
        assert_hydro_published(message, schema: "github.v1.UserProgrammaticAccessRegenerate")
      end
    end
  end

  context "#restrict_not_onboarded_org_pat?" do
    test "returns false when grant does not exist" do
      access = make_user_programmatic_access_with_grant_request(
        target: @org, actor: @user, permissions: { "members" => :read }
      )

      assert_not access.restrict_not_onboarded_org_pat?
    end

    test "returns false when the PAT resource owner is a user" do
      access = make_user_programmatic_access_with_grant(
        target: @user, requester: @user, permissions: { "members" => :read }
      )

      assert_not access.restrict_not_onboarded_org_pat?
    end

    test "returns false when the PAT resource owner is an onboarded org" do
      @org.opt_in_programmatic_access_tokens(actor: @org.admin)
      access = make_user_programmatic_access_with_grant(
        target: @org, requester: @user, permissions: { "members" => :read }
      )

      assert_not access.restrict_not_onboarded_org_pat?
    end

    test "returns true when the PAT resource owner is a non-onboarded org" do
      access = make_user_programmatic_access_with_grant(
        target: @org, requester: @user, permissions: { "members" => :read }
      )

      assert access.restrict_not_onboarded_org_pat?
    end
  end
end
