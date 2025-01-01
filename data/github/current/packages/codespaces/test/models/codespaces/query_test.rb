# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"

class Codespaces::QueryTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper
  include GitHub::LoggerHelper

  setup do
    @user = create(:user)
    @repo = create(:repository, owner: @user, from_example: :pull_request_source)

    @org = create(:organization)
    @org_repo = create(:repository, owner: @org)
    @org.add_member(@user)

    @personal_codespace = create(:codespace, owner: @user, repository: @repo, ref: @repo.default_branch)
    @org_repo_ref_codespace = create(:codespace, owner: @user, repository: @org_repo, ref: @org_repo.default_branch)

    @pull_request = create(:pull_request,
      user: @user,
      repository: @repo,
      base_repository: @repo,
      head_repository: @repo,
      head_ref: "master-merged-topic"
    )

    @pr_codespace = create(:codespace, owner: @user, pull_request: @pull_request)

    # Set up source/fork for forking tests
    @forker = create(:user, login: "forker")
    @source = create(:repository, owner: @user, from_example: :pull_request_source)
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :pull_request_fork)

    @pull_request_from_fork = PullRequest.create_for(
        @source,
        title: "PR from fork into base",
        body: "fork me",
        head: "#{@forker.name}:master-plus-one-commit",
        base: "master",
        user: @forker
    )
    @pull_request_from_fork.fork_collab_allowed!

    @fork_collab_codespace = create(:codespace, :unpushable, owner: @user, pull_request: @pull_request_from_fork)
  end

  def query(**args)
    args[:current_user] = args.key?(:current_user) ? args[:current_user] : @user
    args[:repository] = args.key?(:repository) ? args[:repository] : @repo
    args[:pull_request] = args[:pull_request]
    args[:cap_filter] ||= cap_authorizing_filter
    Codespaces::Query.new(**T.unsafe(**args))
  end

  context "#repository", skip_enterprise: true do
    test "returns the pull request's head repository even if explicitly provided its base repository" do
      q = query(repository: @source, pull_request: @pull_request_from_fork)
      assert_equal q.repository, @pull_request_from_fork.head_repository
    end

    test "returns the repository when not provided with a pull request" do
      q = query(repository: @source)
      assert_equal q.repository, @source
    end
  end

  context "#codespaces", skip_enterprise: true do
    test "returns all codespaces for the user if the context is `accessible`" do
      results = query(
        codespaces_context: Codespaces::Query::ACCESSIBLE_CODESPACES,
      ).codespaces

      assert_same_elements([@personal_codespace, @org_repo_ref_codespace, @pr_codespace, @fork_collab_codespace], results)
    end

    test "returns codespaces scoped to repository when `repository` is present and not pull request" do
      results = query(repository: @repo).codespaces

      assert_same_elements([@personal_codespace, @pr_codespace], results)
    end

    test "returns codespaces for repo when repository is present" do
      forked_repository = create(:fork_repository, forker: @user, fork_repo: @org_repo)
      fork_codespace = create :codespace, owner: @user, repository: forked_repository, ref: "any-branch-name"

      results = query(repository: @org_repo, ref: @org_repo.default_branch).codespaces
      assert_same_elements([@org_repo_ref_codespace, fork_codespace], results)

      results = query(repository: @org_repo, ref: "random-branch").codespaces
      assert_same_elements([@org_repo_ref_codespace, fork_codespace], results)
    end

    test "returns codespaces scoped to repository or direct forks when `repository` is present" do
      forked_repository = create(:fork_repository, forker: @user, fork_repo: @org_repo)
      fork_codespace = create :codespace, owner: @user, repository: forked_repository, ref: "any-branch-name"

      results = query(repository: @org_repo).codespaces
      assert_same_elements([@org_repo_ref_codespace, fork_codespace], results)
    end

    test "returns codespaces scoped to repository and read only parents when `repository` is present" do
      random_user = create(:user)
      codespace = create(:codespace, :unpushable, owner: random_user, repository: @repo, ref: @repo.default_branch)

      forked_repository = create(:fork_repository, forker: random_user, fork_repo: @repo)
      fork_codespace = create :codespace, owner: random_user, repository: forked_repository, ref: "any-branch-name"

      @org_repo
      results = query(current_user: random_user, repository: forked_repository).codespaces

      assert_same_elements([codespace, fork_codespace], results)
    end

    test "returns codespaces scoped to repository without pushable parents when `repository` is present" do
      random_user = create(:user)
      codespace = create(:codespace, owner: random_user, repository: @repo, ref: @repo.default_branch)

      forked_repository = create(:fork_repository, forker: random_user, fork_repo: @repo)
      fork_codespace = create :codespace, owner: random_user, repository: forked_repository, ref: "any-branch-name"

      @org_repo
      results = query(current_user: random_user, repository: forked_repository).codespaces

      assert_same_elements([fork_codespace], results)
    end

    test "returns codespaces scoped to repository when repository is present" do
      forked_repository = create(:fork_repository, forker: @user, fork_repo: @repo, organization: @org)
      fork_codespace = create :codespace, owner: @user, repository: forked_repository, ref: "any-branch-name"

      results = query(repository: @repo, ref: @repo.default_branch).codespaces
      assert_same_elements([@personal_codespace, fork_codespace, @pr_codespace], results)

      results = query(repository: @repo, ref: "random-branch").codespaces
      assert_same_elements([@personal_codespace, fork_codespace, @pr_codespace], results)
    end

    test "does not include codespaces from deleted repositories when repository is present" do
      forked_repository = create(:fork_repository, forker: @user, fork_repo: @repo, organization: @org)
      fork_codespace = create :codespace, owner: @user, repository: forked_repository, ref: "any-branch-name"
      forked_repository.destroy!

      results = query(repository: @repo, ref: @repo.default_branch).codespaces
      assert_same_elements([@personal_codespace, @pr_codespace], results)

      results = query(repository: @repo, ref: "random-branch").codespaces
      assert_same_elements([@personal_codespace, @pr_codespace], results)
    end

    test "returns codespaces scoped to PR from forked repositories" do
      fork_codespace = create(:codespace, owner: @forker, repository: @fork, pull_request: @pull_request_from_fork)
      results = query(current_user: @forker, repository: @source, pull_request: @pull_request_from_fork).codespaces
      assert_includes(results, fork_codespace)
    end

    test "returns nothing if no repository or pull_request is passed" do
      results = query(repository: nil).codespaces

      assert_empty results, "there should be no codespaces returned"
    end

    test "returns codespaces filtering out unauthorized SAML orgs" do
      saml_org = create(:business_plus_org)
      saml_identity = create(:external_identity, org: saml_org)
      saml_user = saml_identity.user

      saml_repo = create(:repository, owner: saml_org)
      saml_repo.add_member_without_validation_or_notifications(saml_user, action: :admin)

      saml_codespace = create(:codespace, repository: saml_repo, owner: saml_user)
      codespace = create(:codespace, owner: saml_user)

      cap_filter = cap_unauthorizing_filter([saml_codespace])
      results = query(
        current_user: saml_user,
        codespaces_context: Codespaces::Query::ACCESSIBLE_CODESPACES,
        cap_filter: cap_filter
      ).codespaces

      assert_same_elements([codespace], results)
    end
  end

  context "#codespaces_count", skip_enterprise: true do
    test "returns a count of codespaces" do
      count = query(repository: @repo).codespaces_count

      assert_equal 2, count
    end
  end

  context "#show_all_accessible_codespaces?" do
    test "is true if the context equals ACCESSIBLE_CODESPACES" do
      object = query(codespaces_context: Codespaces::Query::ACCESSIBLE_CODESPACES)

      assert object.show_all_accessible_codespaces?
    end

    test "is false if the context is not equal to ACCESSIBLE_CODESPACES" do
      object = query

      refute object.show_all_accessible_codespaces?
    end
  end

  context "#build_codespace" do
    test "build a new codespace for the user and repository" do
      new_codespace = query(ref: @repo.default_branch).build_codespace

      assert_equal @user, new_codespace.owner
      assert_equal @repo, new_codespace.repository
    end

    test "builds a codespace for a ref when passed" do
      new_codespace = query(ref: @repo.default_branch).build_codespace

      assert_equal new_codespace.ref, @repo.default_branch
    end

    test "builds a codespace for a PR when no ref passed" do
      new_codespace = query(pull_request: @pull_request).build_codespace

      assert_equal @pull_request, new_codespace.pull_request
    end

    test "includes billable_owner" do
      new_codespace = query(ref: @repo.default_branch).build_codespace
      assert_equal @user, new_codespace.billable_owner
    end
  end

  context "#repository_policy" do
    test "returns a repository policy for the query's repository" do
      refute_nil query(repository: @repo).repository_policy

      repo_without_codespace = create(:repository)
      refute_nil query(repository: repo_without_codespace).repository_policy
    end

    test "returns a repository policy for the pull request's head repository" do
      refute_nil repository_policy = query(repository: @source, pull_request: @pull_request_from_fork).repository_policy
      assert_equal repository_policy.repository, @pull_request_from_fork.head_repository
    end

    test "returns a repository policy for the given repository" do
      q = query(codespaces_context: Codespaces::Query::ACCESSIBLE_CODESPACES)
      refute_nil repository_policy1 = q.repository_policy(repository: @repo)
      refute_nil repository_policy2 = q.repository_policy(repository: @org_repo)
      refute_equal repository_policy1, repository_policy2
    end

    test "differentiates between repository policies for the same repository based on the pull request" do
      q = query(codespaces_context: Codespaces::Query::ACCESSIBLE_CODESPACES)
      refute_nil repository_policy1 = q.repository_policy(repository: @repo, pull_request: @pull_request)
      refute_nil repository_policy2 = q.repository_policy(repository: @repo)
      refute_equal repository_policy1, repository_policy2
    end
  end

  context "#all_accessible_codespaces", skip_enterprise: true do
    test "returns all accessible codespaces regardless of context" do
      q = query(
        codespaces_context: Codespaces::Query::ACCESSIBLE_CODESPACES,
      )
      assert_same_elements([@personal_codespace, @org_repo_ref_codespace, @pr_codespace, @fork_collab_codespace], q.all_accessible_codespaces)

      q = query(
        repository: @personal_codespace.repository
      )
      assert_same_elements([@personal_codespace, @org_repo_ref_codespace, @pr_codespace, @fork_collab_codespace], q.all_accessible_codespaces)
    end

    test "includes SAML-filtered codespaces" do
      saml_org = create(:business_plus_org)
      saml_identity = create(:external_identity, org: saml_org)
      saml_user = saml_identity.user

      saml_repo = create(:repository, owner: saml_org)
      saml_repo.add_member_without_validation_or_notifications(saml_user, action: :admin)

      saml_codespace = create(:codespace, repository: saml_repo, owner: saml_user)
      codespace = create(:codespace, owner: saml_user)

      cap_filter = cap_unauthorizing_filter([saml_codespace])
      q = query(
        current_user: saml_user,
        codespaces_context: Codespaces::Query::ACCESSIBLE_CODESPACES,
        cap_filter: cap_filter
      )

      assert_same_elements([saml_codespace, codespace], q.all_accessible_codespaces)
    end
  end

  context "#at_limit?", skip_enterprise: true do
    test "respects per user limit" do
      Codespaces::Policy.stub(:codespaces_limit, 2) do
        ordinary_user = create(:user)
        disable_feature_flag(:codespaces_per_user_sales_demo_limit, ordinary_user)
        disable_feature_flag(:codespaces_automated_testing, ordinary_user)

        refute Codespaces::Query.new(current_user: ordinary_user).at_limit?

        create(:codespace, owner: ordinary_user)
        refute Codespaces::Query.new(current_user: ordinary_user).at_limit?

        create(:codespace, owner: ordinary_user)
        assert Codespaces::Query.new(current_user: ordinary_user).at_limit?
      end
    end

    test "respects org policy limit" do
      Codespaces::Policy.stub(:codespaces_limit, 2) do
        ordinary_user = create(:user)
        disable_feature_flag(:codespaces_per_user_sales_demo_limit, ordinary_user)
        disable_feature_flag(:codespaces_automated_testing, ordinary_user)

        policy_group_org = create(:policy_group, owner: @org, name: "all repos")
        create(:policy_group_membership, policy_group: policy_group_org, target: @org)
        create(:policy_constraint, policy_group: policy_group_org, maximum_value: 30, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS)

        Codespaces::Query.any_instance.stubs(:all_accessible_codespaces_for_org).returns(%w[codespace1 codespace2])

        assert true, Codespaces::Query.new(current_user: ordinary_user).at_limit?(@org)
      end
    end
  end

  test "inaccessible codespaces do not count toward codespace limit", skip_enterprise: true do
    Codespaces::Policy.stub(:codespaces_limit, 2) do
      user = create(:user)
      owner = create(:user)
      repo = create(:repository, owner: owner)
      disable_feature_flag(:codespaces_per_user_sales_demo_limit, user)
      disable_feature_flag(:codespaces_automated_testing, user)

      create(:codespace, owner: user, repository: repo)
      refute Codespaces::Query.new(current_user: user).at_limit?

      create(:codespace, owner: user, repository: repo)
      assert Codespaces::Query.new(current_user: user).at_limit?

      repo.update(public: false)
      repo.remove_member(user)
      refute Codespaces::Query.new(current_user: user).at_limit?
    end
  end

  context "all_accessible_running_codespaces" do
    test "it does not count inaccessible codespaces" do
      user = create(:user)
      repo = create(:repository)

      # Create a codespace for a public repository the user doesn't own
      codespace = create(:codespace, owner: user, repository: repo)

      assert Codespaces::Query.new(current_user: user).all_accessible_running_codespaces.include?(codespace)

      # Remove the user's access, the codespace should be inaccessible now
      repo.update(public: false)
      repo.remove_member(user)

      refute Codespaces::Query.new(current_user: user).all_accessible_running_codespaces.include?(codespace)
    end

    test "it includes all environment states which consume compute" do
      valid_states = Codespaces::Vscs::State::CONSUMING_COMPUTE_STATES
      valid_states.each do |state|
        user = create(:user)
        codespace = create_codespace_with_environment_details(owner: user, environment_state: state)
        assert Codespaces::Query.new(current_user: user).all_accessible_running_codespaces.include?(codespace)
      end
    end

    test "it excludes all other environment states" do
      invalid_states = Codespaces::Vscs::State::ALL_STATES - Codespaces::Vscs::State::CONSUMING_COMPUTE_STATES
      invalid_states.each do |state|
        user = create(:user)
        codespace = create_codespace_with_environment_details(owner: user, environment_state: state)
        refute Codespaces::Query.new(current_user: user).all_accessible_running_codespaces.include?(codespace)
      end
    end
  end

  def create_codespace_with_environment_details(owner:, environment_state:)
    codespace = create(:codespace, owner: owner)
    codespace.update(environment_data: { id: codespace.guid, friendlyName: codespace.name, state: environment_state })
    codespace
  end
end unless GitHub.enterprise?
