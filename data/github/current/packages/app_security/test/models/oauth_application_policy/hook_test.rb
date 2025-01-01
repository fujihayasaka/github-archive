# typed: true
# frozen_string_literal: true

require "test_helper"

class OauthApplicationPolicyHookTest < GitHub::TestCase
  fixtures do
    @user = create :user, plan: "medium"
    @org = create :organization, admin: @user, plan: "bronze", login: "stark-industries"
    @org.allow_private_repository_forking(actor: @user)
    @oauth_app = create :oauth_application, name: "Janky"
  end

  context "#satisfied?" do
    test "returns true for user-owned repos" do
      repo         = create :repository, owner: @user
      private_repo = create :private_repository, :minimal, owner: @user

      hook              = sample_webhook_installed_by_app_for(repo)
      private_repo_hook = sample_webhook_installed_by_app_for(private_repo)

      assert hook_oap(hook, push_event(hook, repo)).satisfied?
      assert hook_oap(private_repo_hook, push_event(private_repo_hook, private_repo)).satisfied?
    end

    test "returns true for org-owned public repo hooks" do
      @org.enable_oauth_application_restrictions

      repo = create :repository, owner: @org
      hook = sample_webhook_installed_by_app_for(repo)

      assert hook_oap(hook, push_event(hook, repo)).satisfied?
    end

    test "returns true for org-owned private repo hooks with no app restrictions" do
      repo = create :private_repository, owner: @org
      hook = sample_webhook_installed_by_app_for(repo)

      assert hook_oap(hook, push_event(hook, repo)).satisfied?
    end

    test "returns false for org-owned private repo hooks with app restrictions" do
      @org.enable_oauth_application_restrictions

      repo = create :private_repository, owner: @org
      hook = sample_webhook_installed_by_app_for(repo)

      refute hook_oap(hook, push_event(hook, repo)).satisfied?
    end

    test "returns true for org-owned public org hooks" do
      @org.enable_oauth_application_restrictions

      repo = create :repository, owner: @org
      hook = sample_webhook_installed_by_app_for(@org)

      assert hook_oap(hook, push_event(hook, repo)).satisfied?
    end

    test "returns true for org-owned private org hooks with no app restrictions" do
      repo = create :private_repository, owner: @org
      hook = sample_webhook_installed_by_app_for(@org)

      assert hook_oap(hook, push_event(hook, repo)).satisfied?
    end

    test "returns false for org-owned private org hooks with app restrictions" do
      @org.enable_oauth_application_restrictions

      repo = create :private_repository, owner: @org
      hook = sample_webhook_installed_by_app_for(@org)

      refute hook_oap(hook, push_event(hook, repo)).satisfied?
    end

    test "returns true for org hooks where policymaker does not block app" do
      another_org = create :organization,
        login: "another-org",
        plan: "bronze",
        admin: @user,
        business: @org.business

      repo = create :private_repository, owner: @org
      another_org_fork, status = \
        repo.fork forker: @user, org: another_org

      hook = sample_webhook_installed_by_app_for(another_org)

      assert hook_oap(hook, push_event(hook, another_org_fork)).satisfied?
    end

    test "returns false for org hooks when policymaker blocks app" do
      @org.enable_oauth_application_restrictions
      another_org = create :organization,
        login: "another-org",
        plan: "bronze",
        admin: @user

      repo = create :private_repository, owner: @org
      another_org_fork, status = \
        repo.fork forker: @user, org: another_org

      hook = sample_webhook_installed_by_app_for(another_org)

      refute hook_oap(hook, push_event(hook, another_org_fork)).satisfied?
    end

    test "returns false for org hooks when event does not have organization_target" do
      repo = create :private_repository, owner: @org
      hook = sample_webhook_installed_by_app_for(@org)
      event = push_event(hook, repo)
      event.repo = nil

      refute hook_oap(hook, event).satisfied?
    end

    test "returns true for hooks not created by an OAuth app" do
      user = create :user, login: "an-user", plan: "medium"
      org  = create(:organization)
      org.enable_oauth_application_restrictions

      repo = create :private_repository, owner: org
      hook = create :hook,
               installation_target: repo,
               events: %w(push),
               config: { "url" => "http://example.com" },
               active: true,
               creator: @user

      assert hook_oap(hook, push_event(hook, repo)).satisfied?
    end
  end

  private

  def sample_webhook_installed_by_app_for(target)
    create :hook,
      installation_target: target,
      events: %w(push),
      config: { "url" => "http://example.com" },
      active: true,
      oauth_application: @oauth_app,
      creator: @user
  end

  def push_event(hook, repo)
    Hook::Event::PushEvent.new \
      repo: repo,
      before: "sha1",
      after: "sha2",
      ref: "refs/heads/master"
  end

  def hook_oap(hook, hook_event)
    OauthApplicationPolicy::Hook.new(hook, hook_event)
  end
end
