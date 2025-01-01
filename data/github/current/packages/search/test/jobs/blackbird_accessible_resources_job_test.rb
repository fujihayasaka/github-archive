# typed: true
# frozen_string_literal: true

require "test_helper"

class BlackbirdAccessibleResourcesJobTest < GitHub::TestCase
  include ApiProgrammaticGrantHelpers
  include AuthndClientTestHelpers

  AccessibleResources = Hydro::Schemas::Blackbird::V0::Entities::AccessibleResources

  API = ::Search::Blackbird::Client::ACCESS_TOKEN_KIND_API
  WEB = ::Search::Blackbird::Client::ACCESS_TOKEN_KIND_WEB

  def setup
    @key_prefix = "v1"
    @request_id = "request_id"
    @request_user_ip = "127.0.0.1"
  end

  context "locking" do
    test "is noop if acquiring lock fails" do
      mutex_lock_stub = stub
      mutex_lock_stub.expects(:lock).once.raises(GitHub::Redis::Mutex::LockError)
      mutex_lock_stub.expects(:unlock).never
      BlackbirdSearch::Redis.expects(:mutex).once.returns(mutex_lock_stub)

      actor = create(:user)
      user_session = create(:user_session, user: actor)

      result = BlackbirdSearch::Redis.get(key: BlackbirdSearch::Redis.key(key_prefix: @key_prefix, actor_id: actor.id, session_id: user_session.id.to_s))
      assert_nil result.value!

      assert_nothing_raised do
        BlackbirdAccessibleResourcesJob.perform_now(
          actor: actor,
          auth_id: user_session.id,
          auth_type: :user_session,
          expires_at: nil,
          has_lock: false,
          key_prefix: @key_prefix,
          request_id: @request_id,
          request_user_ip: @request_user_ip,
          session_id: user_session.id.to_s,
          token_kind: WEB,
        )
      end

      result = BlackbirdSearch::Redis.get(key: BlackbirdSearch::Redis.key(key_prefix: @key_prefix, actor_id: actor.id, session_id: user_session.id.to_s))
      assert_nil result.value!
    end

    test "always releases lock if exception is raised when setting value in Redis" do
      mutex_lock_stub = stub
      mutex_lock_stub.expects(:lock).once
      mutex_lock_stub.expects(:unlock).once
      BlackbirdSearch::Redis.expects(:mutex).once.returns(mutex_lock_stub)
      BlackbirdSearch::Redis.expects(:set).raises(Redis::BaseError)

      actor = create(:user)
      user_session = create(:user_session, user: actor)

      result = BlackbirdSearch::Redis.get(key: BlackbirdSearch::Redis.key(key_prefix: @key_prefix, actor_id: actor.id, session_id: user_session.id.to_s))
      assert_nil result.value!

      assert_raises(Redis::BaseError) do
        BlackbirdAccessibleResourcesJob.perform_now(
          actor: actor,
          auth_id: user_session.id,
          auth_type: :user_session,
          expires_at: nil,
          has_lock: false,
          key_prefix: @key_prefix,
          request_id: @request_id,
          request_user_ip: "127.0.0.1",
          session_id: user_session.id.to_s,
          token_kind: WEB,
        )
      end

      result = BlackbirdSearch::Redis.get(key: BlackbirdSearch::Redis.key(key_prefix: @key_prefix, actor_id: actor.id, session_id: user_session.id.to_s))
      assert_nil result.value!
    end
  end

  context "user session authorization (i.e. web sessions)" do
    test "acquires lock, computes and sets an accessible resources cache entry" do
      actor = create(:user)
      private_repo = create(:private_repository, owner: actor)
      other_private_repo = create(:private_repository)
      user_session = create(:user_session, user: actor)

      result = BlackbirdSearch::Redis.get(key: BlackbirdSearch::Redis.key(key_prefix: @key_prefix, actor_id: actor.id, session_id: user_session.id.to_s))
      assert_nil result.value!

      BlackbirdAccessibleResourcesJob.perform_now(
        actor: actor,
        auth_id: user_session.id,
        auth_type: :user_session,
        expires_at: nil,
        has_lock: false,
        key_prefix: @key_prefix,
        request_id: @request_id,
        request_user_ip: "127.0.0.1",
        session_id: user_session.id.to_s,
        token_kind: WEB,
      )

      result = BlackbirdSearch::Redis.get(key: BlackbirdSearch::Redis.key(key_prefix: @key_prefix, actor_id: actor.id, session_id: user_session.id.to_s))
      actual_ar = AccessibleResources.decode(result.value!)
      including_emu_orgs = actor.organizations.map { |org| org.business.organization_ids }.flatten.uniq
      expected_ar = AccessibleResources.new(
        accessible_private_repo_ids: [private_repo.id],
        accessible_owner_ids: [actor.id].concat(including_emu_orgs),
        authorized_organization_ids: including_emu_orgs,
        protected_organization_ids: [],
      )
      assert_equal expected_ar, actual_ar
    end
  end

  context "authentication token authorization (i.e. integration installations)" do
    test "computes and sets an accessible resources cache entry" do
      actor = create(:user)
      org = create(:organization)
      org.add_member(actor)
      org_private_repo = create(:private_repository, owner: org)
      actor_private_repo = create(:private_repository, owner: actor)

      installation = make_integration_installation(
        target: org,
        repositories: [org_private_repo],
        permissions: { "metadata" => :read, "contents" => :read },
      )
      auth_token, token = AuthenticationToken.create_for(installation)
      session_id = AuthenticationToken.hash_token(token)

      result = BlackbirdSearch::Redis.get(key: BlackbirdSearch::Redis.key(key_prefix: @key_prefix, actor_id: actor.id, session_id: session_id))
      assert_nil result.value!

      BlackbirdAccessibleResourcesJob.perform_now(
        actor: actor,
        auth_id: auth_token.id,
        auth_type: :authentication_token,
        expires_at: nil,
        has_lock: true,
        key_prefix: @key_prefix,
        request_id: @request_id,
        request_user_ip: "127.0.0.1",
        session_id: session_id,
        token_kind: API,
      )

      result = BlackbirdSearch::Redis.get(key: BlackbirdSearch::Redis.key(key_prefix: @key_prefix, actor_id: actor.id, session_id: session_id))
      assert result.ok?
      actual_ar = AccessibleResources.decode(result.value!)
      expected_ar = AccessibleResources.new(
        accessible_private_repo_ids: [org_private_repo.id],
        accessible_owner_ids: [installation.bot.id, org.id],
        authorized_organization_ids: [org.id],
        protected_organization_ids: [],
      )
      assert_equal expected_ar, actual_ar
    end
  end

  context "oauth access authorization (i.e. legacy PATs)" do
    test "computes and sets an accessible resources cache entry" do
      actor = create(:user)
      actor_private_repo = create(:private_repository, owner: actor)
      org = create(:organization)
      org.add_member(actor)
      org_private_repo = create(:private_repository, owner: org)

      legacy_pat = make_personal_access_token(actor, "repo")
      Organization::CredentialAuthorization.grant(
        organization: org,
        credential: legacy_pat,
        actor: actor,
      )
      session_id = legacy_pat.hashed_token
      result = BlackbirdSearch::Redis.get(key: BlackbirdSearch::Redis.key(key_prefix: @key_prefix, actor_id: actor.id, session_id: session_id))
      assert_nil result.value!

      BlackbirdAccessibleResourcesJob.perform_now(
        actor: actor,
        auth_id: legacy_pat.id,
        auth_type: :oauth_access,
        expires_at: nil,
        has_lock: true,
        key_prefix: @key_prefix,
        request_id: @request_id,
        request_user_ip: "127.0.0.1",
        session_id: session_id,
        token_kind: API,
      )

      result = BlackbirdSearch::Redis.get(key: BlackbirdSearch::Redis.key(key_prefix: @key_prefix, actor_id: actor.id, session_id: session_id))
      assert result.ok?
      actual_ar = AccessibleResources.decode(result.value!)
      expected_ar = AccessibleResources.new(
        accessible_private_repo_ids: [actor_private_repo.id, org_private_repo.id],
        accessible_owner_ids: [actor.id, org.id],
        authorized_organization_ids: [org.id],
        protected_organization_ids: [],
      )
      assert_equal expected_ar, actual_ar
    end
  end

  context "user programmatic access authorization (i.e. fine-grained PATs)" do
    test "computes and sets an accessible resources cache entry" do
      actor = create(:user)
      private_repo1 = create(:private_repository, owner: actor, force_user_owned: true)
      private_repo2 = create(:private_repository, owner: actor, force_user_owned: true)
      org = create(:organization)
      org.add_member(actor)

      with_authnd_stub do
        user_programmatic_access = make_user_programmatic_access_with_grant({
          requester: actor,
          target: actor,
          permissions: { "metadata" => :read, "contents" => :read },
          repositories: [private_repo1],
          repository_selection: :subset,
        })

        stub_authnd_programmatic_access_issue_token
        result = ProgrammaticAccessToken.generate(user_programmatic_access)

        if result.failed?
          raise ArgumentError, "failed to generate programmatic access token"
        end

        stub_authnd_programmatic_access_token(user_programmatic_access, result.value)

        session_id = AuthenticationToken.hash_token(result.value) # session_id for api actors is the hashed token value.
        result = BlackbirdSearch::Redis.get(key: BlackbirdSearch::Redis.key(key_prefix: @key_prefix, actor_id: actor.id, session_id: session_id))
        assert_nil result.value!

        BlackbirdAccessibleResourcesJob.perform_now(
          actor: actor,
          auth_id: user_programmatic_access.id,
          auth_type: :user_programmatic_access,
          expires_at: user_programmatic_access.expires_at,
          has_lock: true,
          key_prefix: @key_prefix,
          request_id: @request_id,
          request_user_ip: "127.0.0.1",
          session_id: session_id,
          token_kind: API,
        )

        result = BlackbirdSearch::Redis.get(key: BlackbirdSearch::Redis.key(key_prefix: @key_prefix, actor_id: actor.id, session_id: session_id))
        assert result.ok?
        actual_ar = AccessibleResources.decode(result.value!)
        expected_ar = AccessibleResources.new(
          accessible_private_repo_ids: [private_repo1.id],
          accessible_owner_ids: [actor.id, org.id],
          authorized_organization_ids: [org.id],
          protected_organization_ids: [],
        )
        assert_equal expected_ar, actual_ar
      end
    end
  end

  context "integration authorization (i.e. enterprise installations)" do
    test "computes and sets an accessible resources cache entry" do
      actor = create(:user)
      org = create(:organization)
      org.add_member(actor)
      org_private_repo1 = create(:private_repository, owner: org)
      org_private_repo2 = create(:private_repository, owner: org)
      actor_private_repo = create(:private_repository, owner: actor)

      enterprise_installation = create(:enterprise_installation, owner: org)
      integration, integration_secret = enterprise_installation.create_github_app
      app_installation = make_integration_installation(integration: integration, target: org, repositories: [org_private_repo1], permissions: { "metadata" => :read, "contents" => :read })
      session_id = AuthenticationToken.hash_token(integration_secret)

      result = BlackbirdSearch::Redis.get(key: BlackbirdSearch::Redis.key(key_prefix: @key_prefix, actor_id: actor.id, session_id: session_id))
      assert_nil result.value!

      BlackbirdAccessibleResourcesJob.perform_now(
        actor: actor,
        auth_id: integration.id,
        auth_type: :integration,
        expires_at: nil,
        has_lock: true,
        key_prefix: @key_prefix,
        request_id: @request_id,
        request_user_ip: "127.0.0.1",
        session_id: session_id,
        token_kind: API,
      )

      result = BlackbirdSearch::Redis.get(key: BlackbirdSearch::Redis.key(key_prefix: @key_prefix, actor_id: actor.id, session_id: session_id))
      assert result.ok?
      actual_ar = AccessibleResources.decode(result.value!)
      expected_ar = AccessibleResources.new(
        accessible_private_repo_ids: [],
        accessible_owner_ids: [app_installation.bot.id],
        authorized_organization_ids: [],
        protected_organization_ids: [],
      )
      assert_equal expected_ar, actual_ar
    end
  end
end
