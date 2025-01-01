# typed: strict
# frozen_string_literal: true
require "test_helper"

class SubIssuesFeatureTest < GitHub::TestCase
  fixtures do
    @org = T.let(create(:organization), T.nilable(Organization))
    @org_member = T.let(create(:verified_user), T.nilable(User))
    @org&.add_member(@org_member)
    @random_user = T.let(create(:verified_user), T.nilable(User))

    @user = T.let(create(:verified_user), T.nilable(User))

    @org_repo = T.let(create(:private_repository, owner: @org), T.nilable(Repository))
    @user_repo = T.let(create(:private_repository, owner: @user), T.nilable(Repository))

    @org_project = T.let(create(:memex_project, owner: @org, creator: @org_member), T.nilable(MemexProject))
    @user_project = T.let(create(:memex_project, owner: @user, creator: @user), T.nilable(MemexProject))
  end

  context "#enabled?" do
    test "returns false when nil is passed" do
      refute SubIssuesFeature.enabled?(nil)
    end

    context "organizations" do
      test "it returns false when feature flag is disabled" do
        raise unless @org
        @org.disable_feature(:sub_issues)

        refute SubIssuesFeature.enabled?(@org)
      end

      test "it returns true when feature flag is enabled for organization" do
        raise unless @org
        @org.enable_feature(:sub_issues)

        assert SubIssuesFeature.enabled?(@org)
      end

      test "it returns true when feature flag is enabled globablly" do
        raise unless @org
        GitHub.flipper[:sub_issues].enable

        assert SubIssuesFeature.enabled?(@org)
      end

      test "it returns false for actor when feature flag is enabled for actor but not organization" do
        raise unless @org && @org_member
        @org_member.enable_feature(:sub_issues)
        @org.disable_feature(:sub_issues)

        refute SubIssuesFeature.enabled?(@org, actor: @org_member)
      end

      test "it returns true for actor when feature flag is enabled for organization and actor is a member" do
        raise unless @org
        @org.enable_feature(:sub_issues)

        assert SubIssuesFeature.enabled?(@org, actor: @org_member)
      end

      test "it returns true for actor when feature flag is enabled for organization but actor is not a member" do
        raise unless @org
        @org.enable_feature(:sub_issues)

        assert SubIssuesFeature.enabled?(@org, actor: @random_user)
      end
    end


    context "users" do
      test "it returns false when feature flag is disabled" do
        raise unless @user
        @user.disable_feature(:sub_issues)

        refute SubIssuesFeature.enabled?(@user)
      end

      test "it returns true when feature flag is enabled for user" do
        raise unless @user
        @user.enable_feature(:sub_issues)

        assert SubIssuesFeature.enabled?(@user)
      end

      test "it returns true when feature flag is enabled globablly" do
        raise unless @user
        GitHub.flipper[:sub_issues].enable

        assert SubIssuesFeature.enabled?(@user)
      end

      test "it returns true for actor when feature flag is enabled for user" do
        raise unless @user && @random_user
        @user.enable_feature(:sub_issues)

        assert SubIssuesFeature.enabled?(@user, actor: @random_user)
      end

      test "it returns false for actor when feature flag is not enabled for user" do
        raise unless @user && @random_user
        @user.disable_feature(:sub_issues)

        refute SubIssuesFeature.enabled?(@user, actor: @random_user)
      end
    end

    context "organization repository" do
      test "returns false when flag is disabled for organization" do
        raise unless @org && @org_repo
        @org.disable_feature(:sub_issues)

        refute SubIssuesFeature.enabled?(@org_repo)
      end

      test "returns false when flag is disabled for repository" do
        raise unless @org && @org_repo
        @org_repo.disable_feature(:sub_issues)

        refute SubIssuesFeature.enabled?(@org_repo)
      end

      test "returns true when flag is enabled for organization" do
        raise unless @org && @org_repo
        @org.enable_feature(:sub_issues)

        assert SubIssuesFeature.enabled?(@org_repo)
      end

      test "returns true when flag is enabled for repository" do
        raise unless @org && @org_repo
        @org_repo.enable_feature(:sub_issues)

        assert SubIssuesFeature.enabled?(@org_repo)
      end

      test "returns false for actor when flag is disabled for organization" do
        raise unless @org && @org_repo && @user
        @org.disable_feature(:sub_issues)

        refute SubIssuesFeature.enabled?(@org_repo, actor: @user)
      end

      test "returns false for actor when flag is disabled for repository" do
        raise unless @org && @org_repo && @user
        @org_repo.disable_feature(:sub_issues)

        refute SubIssuesFeature.enabled?(@org_repo, actor: @user)
      end

      test "returns true for actor when flag is enabled for organization and actor is a member" do
        raise unless @org && @org_repo && @org_member
        @org.enable_feature(:sub_issues)

        assert SubIssuesFeature.enabled?(@org_repo, actor: @org_member)
      end

      test "returns true for actor when flag is enabled for organization and actor is not a member" do
        raise unless @org && @org_repo && @random_user
        @org.enable_feature(:sub_issues)

        assert SubIssuesFeature.enabled?(@org_repo, actor: @random_user)
      end

      test "returns true for actor when flag is enabled for repository" do
        raise unless @org && @org_repo && @user
        @org_repo.enable_feature(:sub_issues)

        assert SubIssuesFeature.enabled?(@org_repo, actor: @user)
      end

      test "returns true for public repository" do
        public_org_repo = T.let(create(:public_repository, owner: @org), T.nilable(Repository))
        raise unless public_org_repo
        public_org_repo.enable_feature(:sub_issues)

        assert SubIssuesFeature.enabled?(public_org_repo)
      end
    end

    context "user repository" do
      test "returns false when flag is disabled for user" do
        raise unless @user && @user_repo
        @user.disable_feature(:sub_issues)

        refute SubIssuesFeature.enabled?(@user_repo)
      end

      test "returns false when flag is disabled for repository" do
        raise unless @user && @user_repo
        @user_repo.disable_feature(:sub_issues)

        refute SubIssuesFeature.enabled?(@user_repo)
      end

      test "returns true when flag is enabled for user" do
        raise unless @user && @user_repo
        @user.enable_feature(:sub_issues)

        assert SubIssuesFeature.enabled?(@user_repo)
      end

      test "returns true when flag is enabled for repository" do
        raise unless @user && @user_repo
        @user_repo.enable_feature(:sub_issues)

        assert SubIssuesFeature.enabled?(@user_repo)
      end

      test "returns false for actor when flag is disabled for user" do
        raise unless @user && @user_repo
        @user.disable_feature(:sub_issues)

        refute SubIssuesFeature.enabled?(@user_repo, actor: @user)
      end

      test "returns false for actor when flag is disabled for repository" do
        raise unless @user && @user_repo
        @user_repo.disable_feature(:sub_issues)

        refute SubIssuesFeature.enabled?(@user_repo, actor: @user)
      end

      test "returns true for actor when flag is enabled for user" do
        raise unless @user && @user_repo
        @user.enable_feature(:sub_issues)

        assert SubIssuesFeature.enabled?(@user_repo, actor: @user)
      end

      test "returns true for actor when flag is enabled for repository" do
        raise unless @user && @user_repo
        @user_repo.enable_feature(:sub_issues)

        assert SubIssuesFeature.enabled?(@user_repo, actor: @user)
      end

      test "returns true for public repository" do
        public_user_repo = T.let(create(:public_repository, owner: @user), T.nilable(Repository))
        raise unless public_user_repo
        public_user_repo.enable_feature(:sub_issues)

        assert SubIssuesFeature.enabled?(public_user_repo)
      end
    end

    context "user project" do
      test "returns true if user has sub-issues enabled" do
        raise unless @user && @user_project
        @user.enable_feature(:sub_issues)

        assert SubIssuesFeature.enabled?(@user_project)
      end

      test "returns true if project has sub-issues enabled" do
        raise unless @user && @user_project
        @user_project.enable_feature(:sub_issues)

        assert SubIssuesFeature.enabled?(@user_project)
      end

      test "returns false if user has project sub-issues disabled" do
        raise unless @user && @user_project
        @user.disable_feature(:sub_issues)

        refute SubIssuesFeature.enabled?(@user_project)
      end

      test "returns true if project is public" do
        public_user_project = T.let(create(:memex_project, owner: @user, creator: @user, public: true), T.nilable(MemexProject))
        raise unless @user && public_user_project
        @user.enable_feature(:sub_issues)

        assert SubIssuesFeature.enabled?(public_user_project)
      end
    end

    context "organization project" do
      test "returns true if org has sub-issues and project sub-issues enabled" do
        raise unless @org && @org_project
        @org.enable_feature(:sub_issues)

        assert SubIssuesFeature.enabled?(@org_project)
      end

      test "returns true if project has sub-issues enabled" do
        raise unless @org && @org_project
        @org_project.enable_feature(:sub_issues)

        assert SubIssuesFeature.enabled?(@org_project)
      end

      test "returns false if org has sub-issues disabled" do
        raise unless @org && @org_project
        @org.disable_feature(:sub_issues)

        refute SubIssuesFeature.enabled?(@org_project)
      end

      test "returns true if project is public" do
        public_org_project = T.let(create(:memex_project, owner: @org, creator: @org_member, public: true), T.nilable(MemexProject))
        raise unless @org && public_org_project
        @org.enable_feature(:sub_issues)

        assert SubIssuesFeature.enabled?(public_org_project)
      end

      test "returns true for non-org member" do
        raise unless @org && @org_project
        @org.enable_feature(:sub_issues)

        assert SubIssuesFeature.enabled?(@org_project, actor: @random_user)
      end
    end
  end
end
