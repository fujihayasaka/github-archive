# typed: true
# frozen_string_literal: true

require "test_helper"

class OauthApplicationPolicyApplicationTest < GitHub::TestCase
  fixtures do
    @user = create :user, plan: "medium"
    @org = create :organization, admin: @user, plan: "bronze", login: "stark-industries"
    @oauth_app = create :oauth_application, name: "Janky"
  end

  context "#satisfied?" do
    test "returns true for users" do
      repo = create :repository, owner: @user
      application = policy_application(repo, @oauth_app)

      assert application.satisfied?
    end

    test "returns true for organizations who have NOT restricted oauth applications" do
      repo = create :repository, owner: @org
      refute_predicate @org, :restricts_oauth_applications?

      application = policy_application(repo, @oauth_app)
      assert application.satisfied?
    end

    test "does not explode for deleted organizations" do
      repo = create(:repository, owner: @org).reload
      application = policy_application(repo, @oauth_app)
      @org.delete

      refute application.satisfied?
    end

    # In the case of private forks for deleted organizations, the owner will
    # not be present but the policymaker will be the forker.
    # https://github.com/github/github/issues/120379
    test "does not explode for private forks for deleted orgs" do

      foreign_org = create :organization, login: "foreign-org", admin: @user
      foreign_org.allow_private_repository_forking(actor: @user)

      repo = create(:private_repository, owner: foreign_org)
      private_fork = create(:fork_repository, forker: @user, fork_repo: repo, organization: @org)
      assert private_fork

      @org.delete
      # The owner should now be nil because the Organization has been deleted.
      assert_nil private_fork.reload.owner

      application = policy_application(private_fork, @oauth_app)

      # The forker (user) does not restrict OAuth applications, so the policy
      # should be satisfied in this case.
      assert_predicate application, :satisfied?
    end
  end

  private

  def policy_application(repo, app)
    OauthApplicationPolicy::Application.new(repo, app)
  end
end
