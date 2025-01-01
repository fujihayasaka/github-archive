# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  class CommandPaletteContextTest < GitHub::TestCase
    include GitHub::CommandPaletteTestHelpers

    fixtures do
      @user = create(:user)
      @org = create(:organization)
      @repo = create(:repository)
    end

    setup do
      @context = build_context(current_user: @user, subject: @repo, scope: @repo)
    end

    test "has a current_user which is a User" do
      assert_equal @user, @context.current_user
    end

    test "has a subject" do
      refute_nil @context.subject
    end

    test "has a cap_filter" do
      refute_nil @context.cap_filter
    end

    test "has a return_to" do
      refute_nil @context.return_to
    end

    test "has a scope which is a Context::Scope" do
      assert @context.scope.is_a?(Context::Scope)
    end

    test "has an optional user session" do
      fake_user_session_context = build_context(current_user: @user, subject: @repo, scope: @repo, user_session: :fake_user_session)
      assert_equal :fake_user_session, fake_user_session_context.user_session

      assert_nil @context.user_session
    end
  end
end

module CommandPalette
  class ContextScopeTest < GitHub::TestCase
    setup do
      @user = build(:user)
      @org = build(:organization, admin: @user)
      @user_repo = build(:repository, owner: @user)
      @org_repo = build(:repository, owner: @org)
    end

    context "has a user" do
      test "#repository returns nil" do
        scope = Context::Scope.new(@user)
        assert_nil scope.repository
      end

      test "#owner returns the user" do
        scope = Context::Scope.new(@user)
        assert_equal @user, scope.owner
      end

      test "has an object" do
        scope = Context::Scope.new(@user)
        assert_equal @user, scope.object
      end

      test "has an type" do
        scope = Context::Scope.new(@user)
        assert_equal User, scope.type
      end

      test "#repository? returns false" do
        scope = Context::Scope.new(@user)
        refute_predicate scope, :repository?
      end

      test "#user? returns true" do
        scope = Context::Scope.new(@user)
        assert_predicate scope, :user?
      end

      test "#organization? returns false" do
        scope = Context::Scope.new(@user)
        refute_predicate scope, :organization?
      end

      test "#user_owned? returns false" do
        scope = Context::Scope.new(@user)
        refute_predicate scope, :user_owned?
      end

      test "#organization_owned? returns false" do
        scope = Context::Scope.new(@user)
        refute_predicate scope, :organization_owned?
      end

      test "#user returns the user" do
        scope = Context::Scope.new(@user)
        assert_equal @user, scope.user
      end

      test "#organization returns nil" do
        scope = Context::Scope.new(@user)
        assert_nil scope.organization
      end

      test "#user_owner returns nil" do
        scope = Context::Scope.new(@user)
        assert_nil scope.user_owner
      end

      test "#organization_owner returns nil" do
        scope = Context::Scope.new(@user)
        assert_nil scope.organization_owner
      end
    end

    context "has an organization" do
      test "#repository returns nil" do
        scope = Context::Scope.new(@org)
        assert_nil scope.repository
      end

      test "#owner returns the org" do
        scope = Context::Scope.new(@org)
        assert_equal @org, scope.owner
      end

      test "has an object" do
        scope = Context::Scope.new(@org)
        assert_equal @org, scope.object
      end

      test "has an type" do
        scope = Context::Scope.new(@org)
        assert_equal Organization, scope.type
      end

      test "#repository? returns false" do
        scope = Context::Scope.new(@org)
        refute_predicate scope, :repository?
      end

      test "#user? returns false" do
        scope = Context::Scope.new(@org)
        refute_predicate scope, :user?
      end

      test "#organization? returns true" do
        scope = Context::Scope.new(@org)
        assert_predicate scope, :organization?
      end

      test "#user_owned? returns false" do
        scope = Context::Scope.new(@org)
        refute_predicate scope, :user_owned?
      end

      test "#organization_owned? returns false" do
        scope = Context::Scope.new(@org)
        refute_predicate scope, :organization_owned?
      end

      test "#user returns nil" do
        scope = Context::Scope.new(@org)
        assert_nil scope.user
      end

      test "#organization returns the org" do
        scope = Context::Scope.new(@org)
        assert_equal @org, scope.organization
      end

      test "#user_owner returns nil" do
        scope = Context::Scope.new(@org)
        assert_nil scope.user_owner
      end

      test "#organization_owner returns nil" do
        scope = Context::Scope.new(@org)
        assert_nil scope.organization_owner
      end
    end

    context "has a repository" do
      test "#repository returns the repo" do
        scope = Context::Scope.new(@user_repo)
        assert_equal @user_repo, scope.repository
      end

      test "#owner returns the owner" do
        scope = Context::Scope.new(@user_repo)
        assert_equal @user_repo.owner, scope.owner
      end

      test "has an object" do
        scope = Context::Scope.new(@user_repo)
        assert_equal @user_repo, scope.object
      end

      test "has an type" do
        scope = Context::Scope.new(@user_repo)
        assert_equal Repository, scope.type
      end

      test "#repository? returns true" do
        scope = Context::Scope.new(@user_repo)
        assert_predicate scope, :repository?
      end

      test "#user? returns false" do
        scope = Context::Scope.new(@user_repo)
        refute_predicate scope, :user?
      end

      test "#organization? returns false" do
        scope = Context::Scope.new(@user_repo)
        refute_predicate scope, :organization?
      end

      context "user_repo" do
        test "#user_owned? returns true" do
          scope = Context::Scope.new(@user_repo)
          assert_predicate scope, :user_owned?
        end

        test "#organization_owned? returns false" do
          scope = Context::Scope.new(@user_repo)
          refute_predicate scope, :organization_owned?
        end

        test "#user_owner returns nil" do
          scope = Context::Scope.new(@user_repo)
          assert_equal @user_repo.owner, scope.user_owner
          assert scope.user_owner.is_a?(User)
        end

        test "#organization_owner returns the org owner" do
          scope = Context::Scope.new(@user_repo)
          assert_nil scope.organization_owner
        end
      end

      context "org_repo" do
        test "#user_owned? returns false" do
          scope = Context::Scope.new(@org_repo)
          refute_predicate scope, :user_owned?
        end

        test "#organization_owned? returns true" do
          scope = Context::Scope.new(@org_repo)
          assert_predicate scope, :organization_owned?
        end

        test "#user_owner returns nil" do
          scope = Context::Scope.new(@org_repo)
          assert_nil scope.user_owner
        end

        test "#organization_owner returns the org owner" do
          scope = Context::Scope.new(@org_repo)
          assert_equal @org_repo.owner, scope.organization_owner
          assert scope.organization_owner.is_a?(Organization)
        end
      end

      test "#user returns the nil" do
        scope = Context::Scope.new(@user_repo)
        assert_nil scope.user
      end

      test "#organization returns nil" do
        scope = Context::Scope.new(@user_repo)
        assert_nil scope.organization
      end
    end
  end
end
