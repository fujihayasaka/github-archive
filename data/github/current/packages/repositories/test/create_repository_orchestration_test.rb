# typed: true
# frozen_string_literal: true

require "test_helper"

class CreateRepositoryOrchestrationTest < GitHub::TestCase
  include GitHub::BrainTree::TestHelper
  include GitHub::ZuoraTestHelper
  include HydroTestHelpers
  include HydroMessageJobTestHelpers
  include DogstatsTestHelpers

  fixtures do
    @user = create(:user)
    @org = create(:organization)

    @biz_org_admin = create(:user)
    @biz_org = create(:organization, plan: GitHub::Plan.business_plus, admins: [@biz_org_admin], seats: 20)
    @business = create(:business, name: "Ian, Inc", owners: [@biz_org_admin], organizations: [@biz_org], seats: 20)
    @biz_org_member = create(:user)
    @biz_org.add_member(@biz_org_member)
    snapshot_spokesdb
  end

  def create_repository(params = {}, repo_class = Repository)
    repo_params = {
      name: "reponame",
      description: "an description",
      public: true,
      user: @user,
    }.merge(params)

    repo_params.delete(:public) if repo_params.key?(:visibility)

    owner = repo_params.delete(:owner)
    billing = repo_params.delete(:billing)
    user = repo_params.delete(:user)
    custom_properties = repo_params.delete(:custom_properties)

    repo_class.handle_creation(
      user,
      owner,
      repo_params,
      reflog_data = {},
      billing,
      custom_properties: custom_properties,
    )
  end

  test "initializes new repo with git daemon serving and template" do
    result = create_repository(owner: @user.login)
    repo = result.repository

    assert_repo_exists   repo
    assert_repo_chmodded repo
  end

  test "auto inits new repository with empty commit" do
    result = Timecop.freeze(Time.utc(2013, 3, 1)) do
      perform_enqueued_hydro_jobs(only: [HydroProfilesOnPushJob]) do
        only = [AddToSearchIndexJob, ContributionsBackfillJob, CreateCheckSuitesJob, DeliverHookEventJob, IndexSourceCodeJob, Newsies::AutoSubscribeUsersToRepositoryJob, Newsies::NotifyListSubscriptionStatusChangeJob, ProcessEventJob, RemoveFromSearchIndexJob, RepositoryDependencyManifestInitializationJob, RepositorySetLicenseJob, UpdateEventFeedsJob, RepositorySyncJob]
        perform_enqueued_jobs(only: only) do
          Time.use_zone "Europe/Moscow" do
            create_repository(owner: @user.to_s,
                              auto_init: true,
                              name: "freshrepo")
          end
        end
      end
    end

    repo = result.repository.reload
    commit = repo.heads.find(repo.default_branch).target

    assert_equal [], commit.parent_oids
    assert_equal "Initial commit", commit.message
    assert_equal repo.owner, commit.author
    assert_equal "2013-03-01 04:00:00 +0400", commit.authored_date.to_s
    assert repo.has_wiki?
    assert repo.wiki_access_to_pushers?
    assert repo.has_downloads?
    assert repo.has_issues?

    assert CommitContributions.domain.is_contributor?(user: @user, repository: repo)
  end

  test "auto inits new repository with license file and sets license" do
    result = perform_enqueued_hydro_jobs(only: [HydroProfilesOnPushJob, HydroRepositoriesOnPushJob]) do
      only = [ContributionsBackfillJob, RepositorySetLicenseJob]
      perform_enqueued_jobs(only: only) do
        create_repository({
          owner: @user.to_s,
          auto_init: true,
          license_template: "mit",
        })
      end
    end

    repo = result.repository.reload

    repo.clear_ref_cache

    commit = repo.heads[repo.default_branch].target
    assert_equal "Initial commit", commit.message
    assert_equal repo.owner, commit.author

    refute_nil repo.blob(commit.oid, "LICENSE")
    assert repo.repository_license
    assert_equal License["mit"], repo.repository_license.license

    assert CommitContributions.domain.is_contributor?(user: @user, repository: repo)
  end

  test "initializes new repo with a wiki" do
    result = create_repository(owner: @user.to_s, has_wiki: false)
    repo = result.repository

    assert !repo.has_wiki?
  end

  test "initializes new repo which doesn't support wikis without wiki" do
    result = create_repository(owner: @user.to_s, private: true, has_wiki: true)
    repo = result.repository

    # The repo should only have a wiki if the plan supports it
    assert_equal repo.plan_supports?(:wikis), repo.has_wiki?
  end

  test "initializes new public repo by default with wiki" do
    result = create_repository(owner: @user.to_s, private: false)
    repo = result.repository

    assert repo.has_wiki?
  end

  test "initializes new repo with issues" do
    result = create_repository(owner: @user.to_s, has_issues: false)
    repo = result.repository

    assert !repo.has_issues?
  end

  test "initializes new repo with downloads" do
    result = create_repository(owner: @user.to_s, has_downloads: false)
    repo = result.repository

    assert !repo.has_downloads?
  end

  test "records user that created the repo" do
    result = create_repository(owner: @user.to_s)
    repo = Repository.find(result.repository.id)
    assert_equal @user, repo.created_by
  end

  context "set custom properties" do
    test "skips creating properties if owner is not an org" do
      create :custom_property_definition, source: @org, property_name: "env"

      result = create_repository(owner: @user.login, user: @user, custom_properties: { "env" => "prod" })
      assert Repository.find(result.repository.id)
      assert_equal CustomPropertyValue.for_target(result.repository), []
    end

    test "creates new repo with custom properties" do
      create :custom_property_definition, source: @org, property_name: "env"

      result = create_repository(owner: @org.name, user: @org.admin, custom_properties: { "env" => "prod" })
      assert Repository.find(result.repository.id)
      assert_equal CustomPropertyValue.for_target(result.repository).map { |p| [p.property_name, p.value] }, [%w[env prod]]
    end

    test "fails to create a repo if properties schema is invalid" do
      result = create_repository(owner: @org.name, user: @org.admin, custom_properties: { "unknown" => "value" })
      refute result.success
      assert_equal result.error_message, "Unexpected property 'unknown'"
      assert_equal CustomPropertyValue.for_target(result.repository), []
    end

    test "fails to create a repo if properties values are invalid" do
      create :custom_property_definition, source: @org, property_name: "env"

      result = create_repository(owner: @org.name, user: @org.admin, custom_properties: { "env" => "invalid\"value" })
      refute result.success
      assert_equal result.error_message, "Property 'env' value has invalid characters: \""
      assert_equal CustomPropertyValue.for_target(result.repository), []
    end

    test "fails to create a repo if user does not have permissions to set properties" do
      create :custom_property_definition, source: @org, property_name: "env"

      @org.allow_members_can_create_repositories(actor: @user)
      @org.add_member(@user)

      result = create_repository(owner: @org.name, user: @user, custom_properties: { "env" => "prod" })
      refute result.success
      assert_equal result.error_message, "User does not have permission to set custom properties: env"
      assert_equal CustomPropertyValue.for_target(result.repository), []
    end

    test "create a repo when requested by an org member user and custom property is editable by repo admin" do
      create :custom_property_definition, source: @org, property_name: "env", values_editable_by: "org_and_repo_actors"

      @org.allow_members_can_create_repositories(actor: @user)
      @org.add_member(@user)

      result = create_repository(owner: @org.name, user: @user, custom_properties: { "env" => "prod" })

      assert Repository.find(result.repository.id)
      assert_equal CustomPropertyValue.for_target(result.repository).map { |p| [p.property_name, p.value] }, [%w[env prod]]
    end

    test "fails to create a repo when requested by an org member user and custom property is not editable by repo admin" do
      create :custom_property_definition, source: @org, property_name: "env"

      @org.allow_members_can_create_repositories(actor: @user)
      @org.add_member(@user)

      result = create_repository(owner: @org.name, user: @user, custom_properties: { "env" => "prod" })
      refute result.success
      assert_equal result.error_message, "User does not have permission to set custom properties: env"
      assert_equal CustomPropertyValue.for_target(result.repository), []
    end

    test "fails to create a repo when requested by an org member user and some of the custom properties is not editable by repo admin" do
      create :custom_property_definition, source: @org, property_name: "env", values_editable_by: "org_and_repo_actors"
      create :custom_property_definition, source: @org, property_name: "language"

      @org.allow_members_can_create_repositories(actor: @user)
      @org.add_member(@user)

      result = create_repository(owner: @org.name, user: @user, custom_properties: { "env" => "prod", "language" => "ruby" })
      refute result.success
      assert_equal result.error_message, "User does not have permission to set custom properties: language"
      assert_equal CustomPropertyValue.for_target(result.repository), []
    end

    test "fails to create a repo when requested by an org member user and invalid custom property format" do
      create :custom_property_definition, :single_select, source: @org, property_name: "env", required: true, default_value: "test", allowed_values: %w[test prod staging], values_editable_by: "org_and_repo_actors"

      @org.allow_members_can_create_repositories(actor: @user)
      @org.add_member(@user)

      result = create_repository(owner: @org.name, user: @user, custom_properties: { "env" => "production" })
      refute result.success
      assert_equal result.error_message, "Value 'production' is not allowed for property 'env'"
      assert_equal CustomPropertyValue.for_target(result.repository), []
    end
  end

  test "records orchestration for creating the repo" do
    result = create_repository(owner: @user.to_s)
    repo = Repository.find(result.repository.id)
    orc = CreateRepositoryOrchestration.find_by(repository_id: repo.id)
    refute_nil orc
  end

  test "skips validation on an orchestration" do
    orchestration = RepositoryOrchestration.create_repository(
      actor: @user,
      owner_login: @user.name,
      repo_attributes: { name: "snowflake", owner: @user },
      skip_validation: true,
    )
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      orchestration.execute
    end

    assert_equal :succeeded, orchestration.reload.state.to_sym
    refute_nil orchestration.repository
  end

  test "fails with skipping validation when creating an invalid repo" do
    orchestration = RepositoryOrchestration.create_repository(
      actor: @user,
      owner_login: @user.name,
      repo_attributes: { name: "snowflake" }, # Repo doesn't have an owner, which is invalid
      skip_validation: true,
    )

    orchestration.execute

    assert_equal :skipped, orchestration.state.to_sym
    assert_equal "Repository creation failed.", orchestration.error_message
    assert_equal "record invalid on saving repository", orchestration.logged_error
    assert_nil orchestration.repository
  end

  test "refuses to retry orchestration" do
    orchestration = RepositoryOrchestration.create_repository(
      actor: @user,
      owner_login: @user.name,
      repo_attributes: { name: "snowflake" },
    )

    orchestration = orchestration.class.find(orchestration.id)
    orchestration.execute

    assert_equal :skipped, orchestration.state.to_sym
    assert_equal "Cannot retry creation.", orchestration.error_message
    assert_nil orchestration.repository
  end

  test "retries orchestration steps when max_attempts is greater than 1 and create_repository fails transactionally then succeeds" do
    # Create a failure in the create_repository transaction
    Repository.any_instance.stubs(:has_wiki?).raises(ActiveRecord::ConnectionFailed.new).then.returns(true)
    result = create_repository(owner: @user.name, name: "snowflake")

    assert result.success
    assert Repository.exists?(result.repository.id)
    assert RepositoryNetwork.exists?(result.repository.network_id)
    assert_dogstats_increment(1, "repository_orchestration.step.error", tags: ["step:create_repository"])
    assert_dogstats_increment(1, "repository_orchestration.step.retry", tags: ["step:create_repository"])
  end

  test "retries orchestration steps when max_attempts is greater than 1 and create_repository fails transactionally" do
    # Create a failure in the create_repository transaction
    Repository.any_instance.stubs(:has_wiki?).raises(ActiveRecord::ConnectionFailed.new)
    # This will raise on the second failed attempt
    assert_raises ActiveRecord::ConnectionFailed do
      create_repository(owner: @user.name, name: "snowflake")
    end

    assert_equal 0, Repository.count
    assert_equal 0, RepositoryNetwork.count
    assert_dogstats_increment(2, "repository_orchestration.step.error", tags: ["step:create_repository"])
    assert_dogstats_increment(1, "repository_orchestration.step.retry", tags: ["step:create_repository"])
  end

  test "does not retry create_repository when max_attempts is greater than 1 and create_repository fails non-transactionally" do
    # Create a failure outside the create_repository transaction (after_commit)
    RepositoryNetwork.any_instance.stubs(:owner_disable_check).raises(ActiveRecord::ConnectionFailed.new).then.returns(true)
    result = create_repository(owner: @user.name, name: "snowflake")

    refute result.success
    refute_nil result.error_message
    # Records still exist, since the transaction did complete
    assert Repository.exists?(result.repository.id)
    assert RepositoryNetwork.exists?(result.repository.network_id)
    assert_dogstats_increment(1, "repository_orchestration.step.error", tags: ["step:create_repository"])
    assert_dogstats_increment(1, "repository_orchestration.step.retry", tags: ["step:create_repository"])
  end

  test "auto inits new repository with gitignore file" do
    result = create_repository({
      owner: @user.to_s,
      auto_init: true,
      gitignore_template: "Ruby",
    })
    repo = result.repository

    commit = repo.heads.find(repo.default_branch).target
    assert_equal [], commit.parent_oids
    assert_equal "Initial commit", commit.message
    assert_equal repo.owner, commit.author

    _, entries = repo.tree_entries(repo.heads[repo.default_branch].target_oid, "/")
    assert_equal %w[.gitignore README.md], entries.map(&:name).sort
  end

  test "auto inits new repository with README.md file" do
    result = create_repository({
      owner: @user.to_s,
      auto_init: true,
      gitignore_template: "Ruby",
    })
    repo = result.repository

    commit = repo.heads.find(repo.default_branch).target
    assert_equal [], commit.parent_oids
    assert_equal "Initial commit", commit.message
    assert_equal repo.owner, commit.author

    blob = repo.blob(commit.oid, "README.md")
    assert_equal "# #{repo.name}\n#{repo.description}\n",
      blob.data
  end

  test "associates the repo with a team if a team_id is specified" do
    @org.add_admin(@user) # so the user can create in the org
    team = create :team, organization: @org
    team.add_member @user

    result = create_repository(owner: @org.name, team_id: team.id.to_s)
    assert result.success, result.error_message
    repo = result.repository
    assert_includes team.batched_repositories, repo
  end

  test "does not associate the repo with a team if the owner isn't an org" do
    team = create :team, organization: @org
    team.add_member @user

    result = create_repository(owner: @user.login, team_id: team.id.to_s)
    assert result.success
    repo = result.repository
    refute_includes team.batched_repositories, repo
  end

  [
    ["disallow_members_can_create_repositories", "member", "public", true],
    ["disallow_members_can_create_repositories", "admin", "public", false],
    ["disallow_members_can_create_repositories", "member", "private", true],
    ["disallow_members_can_create_repositories", "admin", "private", false],
    ["disallow_members_can_create_repositories", "member", "anything", true],
    ["disallow_members_can_create_repositories", "admin", "anything", true],
    ["disallow_members_can_create_public_repositories", "member", "public", true],
    ["disallow_members_can_create_public_repositories", "admin", "public", false],
    ["disallow_members_can_create_public_repositories", "member", "private", false],
    ["disallow_members_can_create_public_repositories", "admin", "private", false],
    ["disallow_members_can_create_public_repositories", "member", "anything", true],
    ["disallow_members_can_create_public_repositories", "admin", "anything", true],
  ].each do |method, user_type, repo_visibility, prevents|
    test "#{method} #{prevents ? "prevents" : "does not prevent"} #{repo_visibility} repo creation by a #{user_type}" do
      org_admin = create(:user)
      member = create(:user)
      org = create(:organization, plan: GitHub::Plan.business_plus, admins: [org_admin])
      org.add_member(member)
      case method
      when "disallow_members_can_create_repositories"
        org.disallow_members_can_create_repositories(actor: org_admin)
      when "disallow_members_can_create_public_repositories"
        org.disallow_members_can_create_public_repositories(actor: org_admin)
      end
      user = user_type == "admin" ? org_admin : member
      public_value = case repo_visibility
      when "private"
        false
      when "public"
        true
      else
        repo_visibility
      end
      result = create_repository(user: user, owner: org.name, public: public_value)
      assert result.success != prevents
      assert result.allowed != prevents
    end
  end

  [
    ["member", true, true, true],
    ["member", true, true, false],
    ["member", true, false, true],
    ["member", true, false, false],
    ["member", false, true, true],
    ["member", false, true, false],
    ["member", false, false, true],
    ["member", false, false, false],
    ["admin", true, true, true],
    ["admin", true, true, false],
    ["admin", true, false, true],
    ["admin", true, false, false],
    ["admin", false, true, true],
    ["admin", false, true, false],
    ["admin", false, false, true],
    ["admin", false, false, false],
  ].each do |user_type, allow_public, allow_private, allow_internal|
    test "allow_members_can_create_repositories_with_visibilities #{user_type}-#{allow_public}-#{allow_private}-#{allow_internal}", skip_enterprise: true do
      @biz_org.allow_members_can_create_repositories_with_visibilities(actor: @biz_org_admin,
        public_visibility: allow_public, private_visibility: allow_private, internal_visibility: allow_internal)

      creator = user_type == "admin" ? @biz_org_admin : @biz_org_member
      prefix = SecureRandom.hex(4)
      Repository::VISIBILITIES.each do |visibility|
        name = "#{prefix}-#{visibility}"
        result = Repository.handle_creation(creator, @biz_org.name, { name: name, visibility: visibility })

        if user_type == "admin"
          allowed = true
        else
          allowed = allow_public if visibility == "public"
          allowed = allow_private if visibility == "private"
          allowed = allow_internal if visibility == "internal"
        end
        assert_equal allowed || user_type == "admin", result.success, "visibility: #{visibility}"
        assert_equal allowed || user_type == "admin", result.allowed, "visibility: #{visibility}"
      end
    end
  end

  test "gives creator admin access for an org-owned repo created by a non-org-owner" do
    GitHub.newsies.get_and_update_settings(@user) do |settings|
      settings.auto_subscribe = true
    end
    @org.allow_members_can_create_repositories(actor: @user)
    @org.add_member(@user)

    ActionMailer::Base.deliveries.clear
    result = create_repository(owner: @org.name)
    repo = result.repository

    assert result.success
    assert repo.adminable_by?(@user)
    assert_equal 0, ActionMailer::Base.deliveries.size
    assert_equal true, GitHub.newsies.subscription_status(@user, repo).valid?
  end

  if GitHub.billing_enabled?
    test "providing valid billing details enables the user" do
      FakeZuora.mock

      @user.disable!

      result = create_repository(
        owner: @user.to_s,
        name: "test",
        public: false,
        billing: zuora_parsed_payment_details,
      )

      @user.reload

      assert result.success?
      assert_equal "free", @user.plan.name
      refute_predicate @user, :disabled?
    end

    test "users should be able to create a private repo" do
      result = create_repository(owner: @user.to_s,
                                 name: "test",
                                 public: false)

      assert result.success?
      assert_nil result.error_message, "error message should be nil: #{result.error_message}"
    end

    test "creating a public repo should publish a CREATED event for search indexing", skip_enterprise: true do
      result = create_repository(owner: @user.to_s,
                                 name: "geyser_test_repo",
                                 public: true)

      assert result.success?
      assert_nil result.error_message, "error message should be nil: #{result.error_message}"

      repo = Repository.where(name: result.repository.name).first!
      assert_equal repo.id, result.repository.id

      assert_hydro_published({
        change: :CREATED,
        repository: Hydro::EntitySerializer.repository(repo),
        ref: "refs/heads/#{repo.default_branch}",
        owner_name: repo.owner&.name,
      }, schema: "github.search.v0.RepositoryChanged", ignore_extra_keys: true)

      assert_hydro_messages(count: 1, schema: "github.search.v0.RepositoryChanged")
    end

    test "creating a private repo should publish a CREATED event for search indexing", skip_enterprise: true do
      result = create_repository(owner: @user.to_s,
                                 name: "geyser_test_priv_repo",
                                 public: true)

      assert result.success?
      assert_nil result.error_message, "error message should be nil: #{result.error_message}"

      repo = Repository.where(name: result.repository.name).first!
      assert_equal repo.id, result.repository.id

      assert_hydro_published({
        change: :CREATED,
        repository: Hydro::EntitySerializer.repository(repo),
        ref: "refs/heads/#{repo.default_branch}",
        owner_name: repo.owner&.name,
      }, schema: "github.search.v0.RepositoryChanged", ignore_extra_keys: true)

      assert_hydro_messages(count: 1, schema: "github.search.v0.RepositoryChanged")
    end

    test "users should be able to create a private repo even if are locked on billing" do
      @user.update_attribute :plan, "pro"
      @user.disable!

      result = create_repository(owner: @user.to_s,
                                 name: "test",
                                 public: false)

      assert result.success?
      assert_nil result.error_message, "error message should be nil: #{result.error_message}"
    end
  end

  test "sets allowed merge methods as specified" do
    result = create_repository({
      owner: @user.name,
      name: "snowflake",
    })

    assert result.success
    assert_predicate result.repository, :merge_commit_allowed?
    assert_predicate result.repository, :squash_merge_allowed?
    assert_predicate result.repository, :rebase_merge_allowed?
    refute_predicate result.repository, :squash_merge_commit_title_pr_title_enabled?

    result = create_repository({
      owner: @user.name,
      name: "snowflake1",
      allow_merge_commit: false,
    })

    assert result.success
    refute_predicate result.repository, :merge_commit_allowed?
    assert_predicate result.repository, :squash_merge_allowed?
    assert_predicate result.repository, :rebase_merge_allowed?
    refute_predicate result.repository, :squash_merge_commit_title_pr_title_enabled?

    result = create_repository({
      owner: @user.name,
      name: "snowflake2",
      allow_squash_merge: false,
    })

    assert result.success
    assert_predicate result.repository, :merge_commit_allowed?
    refute_predicate result.repository, :squash_merge_allowed?
    assert_predicate result.repository, :rebase_merge_allowed?
    refute_predicate result.repository, :squash_merge_commit_title_pr_title_enabled?

    result = create_repository({
      owner: @user.name,
      name: "snowflake3",
      allow_rebase_merge: false,
    })

    assert result.success
    assert_predicate result.repository, :merge_commit_allowed?
    assert_predicate result.repository, :squash_merge_allowed?
    refute_predicate result.repository, :rebase_merge_allowed?
    refute_predicate result.repository, :squash_merge_commit_title_pr_title_enabled?
  end

  test "errors out when owner is nil or unknown" do
    e = assert_raises(ArgumentError) do
      create_repository(owner: nil)
    end
    assert_equal "owner can not be nil", e.message

    e = assert_raises(ArgumentError) do
      create_repository(owner: "timbl")
    end
    assert_equal 'unknown owner: "timbl"', e.message
  end

  test "errors out when name already exists on owner" do
    result = create_repository(owner: @user.name, name: "snowflake")
    assert result.success

    result = create_repository(owner: @user.name, name: "snowflake")
    assert !result.success
    assert result.repository
    assert result.repository.errors[:name].any?
  end

  test "errors out when name already exists on owner (using uniq db index)" do
    result = create_repository(owner: @user.name, name: "snowflake")
    assert result.success

    # Stub Repository uniqueness validation to exercise database uniq constraint
    Repository.any_instance.stubs(ensure_uniqueness_of_name: true)

    result = create_repository(owner: @user.name, name: "snowflake")
    assert !result.success
    assert result.repository
    assert result.repository.errors[:name].any?
  end

  test "errors out when name already exists on owner (using model validation on repo save)" do
    result = create_repository(owner: @user.name, name: "snowflake")
    assert result.success

    # Stub validation when creating orchestration, so that duplicate name is allowed
    Repository.any_instance.stubs(valid?: true)
    orchestration = RepositoryOrchestration.create_repository(
      actor: @user,
      owner_login: @user.name,
      repo_attributes: { name: "snowflake" },
    )
    # But then unstub, so that when calling repository.save!, we have a validation error
    Repository.any_instance.unstub(:valid?)
    orchestration.execute

    assert orchestration.skipped?
    assert orchestration.built_repository
    assert orchestration.error_message
    assert orchestration.built_repository.errors[:name].any?
  end

  test "errors out when the namespace is retired and not claimable" do
    login = @user.login
    create(:retired_namespace, owner: @user, name: "retired")
    @user.destroy!
    ReservedLogin.untombstone!(login)
    new_user = create(:user, login: login)
    result = create_repository(owner: new_user.name, name: "retired")
    refute_predicate result, :success?
    assert result.repository
    assert_equal ["has been retired and cannot be reused"], result.repository.errors[:name]
  end

  test "errors out when the namespace is retired and owner_id is nil" do
    namespace = create(:retired_namespace, owner: @user, name: "retired")
    namespace.update!(owner_id: nil)

    result = create_repository(owner: @user.name, name: "retired")
    refute_predicate result, :success?
    assert result.repository
    assert_equal ["has been retired and cannot be reused"], result.repository.errors[:name]
  end

  test "allows creation when namespace is retired but claimable by owner" do
    create(:retired_namespace, owner: @user, name: "retired")

    result = create_repository(owner: @user.name, name: "retired")
    assert_predicate result, :success?
    assert result.repository
    assert_empty result.repository.errors[:name]
  end

  test "errors out when creation is disallowed" do
    result = create_repository(owner: @org.name)
    assert !result.success
    assert !result.allowed
    refute_nil result.repository
    assert result.repository.new_record?
  end

  test "errors out when owner is deleted via validation" do
    org = create(:organization)
    org.async_destroy(org.owner)
    result = create_repository(owner: org.login, user: org.admin, public: false)

    refute result.success
    assert result.repository.new_record?
    assert_match /Owner is being deleted/, result.error_message
  end

  test "errors when owner is over repo limit" do
    create(:private_repository, owner: @user)
    limiter = RepositoryLimit.new(@user)
    limiter.override(soft: 1, hard: 2)

    result = create_repository(owner: @user.login, name: "first")
    assert result.success?

    result = create_repository(owner: @user.login, name: "second")
    if limiter.enabled?
      refute result.success?, "orchestration expected to fail"
      assert result.repository.new_record?, "repo was created"
      assert_equal "Owner is over repository limit.", result.error_message
    else
      assert result.success?
    end
  end

  test "errors out when owner is deleted" do
    org = create(:organization)
    #
    # Simulate validation happening first, and then deleting the org
    # This is realistic since create_repository is a long running step
    orc = RepositoryOrchestration.create_repository(
      actor: org.admin,
      owner_login: org.login,
      repo_attributes: { name: "foo", public: false },
    )
    org.async_destroy(org.owner)
    orc.execute

    refute orc.repository&.active
    assert_equal "skipped", orc.state
  end

  test "errors out when all merge methods are disabled" do
    result = assert_no_difference -> { Repository.count } do
      create_repository({
        owner: @user.name,
        name: "snowflake",
        allow_merge_commit: false,
        allow_squash_merge: false,
        allow_rebase_merge: false,
      })
    end

    refute result.success
    assert result.allowed
    assert result.repository
    assert_equal "pull request merge method error", result.logged_error
    refute_empty result.repository.errors
    assert_equal ["Sorry, you need to allow at least one merge strategy. (no_merge_method)"], result.repository.errors[:base]
  end

  test "errors out when use_squash_pr_title is nil or false, and squash_merge_commit_message is PR_BODY " do
    result = assert_no_difference -> { Repository.count } do
      create_repository({
        owner: @user.name,
        name: "snowflake",
        allow_merge_commit: true,
        use_squash_pr_title_as_default: false,
        squash_merge_commit_message: "PR_BODY",
      })
    end

    refute result.success
    assert_equal "Repository creation failed.", result.error_message
    assert_equal "pull request merge method error", result.logged_error
    refute_empty result.repository.errors
    assert_equal ["Sorry, invalid setting combination. The following are valid combinations for the squash commit title and message: PR_TITLE and PR_BODY, PR_TITLE and BLANK, PR_TITLE and COMMIT_MESSAGES, COMMIT_OR_PR_TITLE and COMMIT_MESSAGES. (invalid_squash_commit_setting_combo)"], result.repository.errors[:base]
  end

  test "fails when squash merge is disallowed but non-default message and title settings are passed " do
    result = assert_no_difference -> { Repository.count } do
      create_repository({
        owner: @user.name,
        name: "snowflake",
        allow_squash_merge: false,
        squash_merge_commit_title: "PR_TITLE",
        squash_merge_commit_message: "BLANK"
      })
    end

    refute result.success
    assert_equal "Repository creation failed.", result.error_message
    assert_equal "pull request merge method error", result.logged_error
    refute_empty result.repository.errors
    assert_match /no_squash_merge_strategy/, result.repository.errors[:base].first
  end

  test "succeeds when squash merge is disallowed but default message and title settings are passed " do
    result = create_repository({
      owner: @user.name,
      name: "snowflake",
      allow_squash_merge: false,
      squash_merge_commit_title: "COMMIT_OR_PR_TITLE",
      squash_merge_commit_message: "COMMIT_MESSAGES"
    })

    assert result.success
    refute_predicate result.repository, :squash_merge_allowed?
    assert_equal "COMMIT_OR_PR_TITLE", result.repository.squash_merge_commit_title_setting
    assert_equal "COMMIT_MESSAGES", result.repository.squash_merge_commit_message_setting
  end

  test "fails when merge commit is disallowed but non-default message and title settings are passed " do
    result = assert_no_difference -> { Repository.count } do
      create_repository({
        owner: @user.name,
        name: "snowflake",
        allow_merge_commit: false,
        merge_commit_title: "PR_TITLE",
        merge_commit_message: "BLANK"
      })
    end

    refute result.success
    assert_equal "Repository creation failed.", result.error_message
    assert_equal "pull request merge method error", result.logged_error
    refute_empty result.repository.errors
    assert_match /no_merge_strategy/, result.repository.errors[:base].first
  end

  test "succeeds when merge commit is disallowed but default message and title settings are passed " do
    result = create_repository({
      owner: @user.name,
      name: "snowflake",
      allow_merge_commit: false,
      merge_commit_title: "MERGE_MESSAGE",
      merge_commit_message: "PR_TITLE"
    })

    assert result.success
    refute_predicate result.repository, :merge_commit_allowed?
    assert_equal "MERGE_MESSAGE", result.repository.merge_commit_title_setting
    assert_equal "PR_TITLE", result.repository.merge_commit_message_setting
  end

  # https://github.com/github/web-support/issues/1885
  test "doesn't update the user's plan when repo creation fails without a plan change" do
    create_repository(owner: @user.login, name: "dup")

    # This is very brittle, but it wasn't clear how to test this
    # another way. :\
    User.any_instance.expects(:update!).never

    # This will fail, as the name matches an existing repo for the same owner
    result = create_repository(owner: @user.login, name: "dup")

    refute result.success
  end

  test "creates inactive repository when spokes creation fails" do
    RepositoryNetwork.any_instance.stubs(:initialize_placeholder_network_replicas).raises(StandardError)
    result = create_repository(owner: @user.to_s)
    repo = result.repository.reload

    refute result.success
    assert_equal "Repository creation failed.", result.error_message
    assert_equal "failed to create repo in spokes", result.logged_error
    assert_nil repo.active
    assert_nil repo.deleted_at
  end

  test "creates repository which is created in spokes but fails to initialize templates" do
    Repository.any_instance.expects(:initialize_git_repository_templates).raises(StandardError)
    result = create_repository(owner: @user.to_s, auto_init: true)
    repo = result.repository.reload

    refute result.success
    assert_equal "Repository creation failed.", result.error_message
    assert_equal "failed to create repo in spokes", result.logged_error
    assert_nil repo.active
    assert_nil repo.deleted_at
    # Repo should be writeable, but empty, since init of files fails
    assert repo.ready_for_writes?
    assert repo.empty?
  end

  test "creates repository with correct public_fork_count" do
    result = create_repository(owner: @user.to_s, public: true)
    repo = result.repository

    assert result.success
    assert_equal 0, repo.public_fork_count
  end

  test "does not create repository with invalid name" do
    # Repo is created with corrected name
    result = create_repository(owner: @user.to_s, name: "spaced out name")
    assert_equal "spaced-out-name", result.repository.name

    # Creating again with bad name should lead to repo not being created at all
    result = create_repository(owner: @user.to_s, name: "spaced out name")

    refute result.success
    refute result.repository.persisted?
  end

  test "does not create repository with .wiki ending" do
    result = create_repository(owner: @user.to_s, name: "uhoh.wiki")

    refute result.success
    refute result.repository.persisted?
  end

  context "internal visibility" do
    test "creates repository with internal visibility" do
      result = Repository.handle_creation(@biz_org_admin, @biz_org.login, { name: "internal1", visibility: Repository::INTERNAL_VISIBILITY })
      assert_predicate result, :success
      refute_predicate result.repository, :public?
      assert_predicate result.repository, :internal?
    end

    test "disallows providing both public and visibility parameters" do
      e = assert_raises(ArgumentError) do
        Repository.handle_creation(@biz_org_admin, @biz_org.login, { name: "internal2", visibility: Repository::INTERNAL_VISIBILITY, public: false })
      end
      assert_match /cannot have both/, e.message
    end

    test "Returns a sensible error when provided invalid visiblity" do
      result = Repository.handle_creation(@biz_org_admin, @biz_org.login, { name: "error-test", visibility: "wutnow" })
      refute result.success
      assert_match /Invalid attribute value/, result.error_message
    end

    test "Returns an error when provided internal visibility for unsupported owner" do
      user = create(:user)
      org = create(:organization, admin: user)
      result = Repository.handle_creation(user, org.login, { name: "internal-test1", visibility: "internal" })
      refute result.success
      assert_match "Only organizations associated with an enterprise can set visibility to internal", result.error_message
    end

    test "Fails with correct error when creation attempted by ofac-restricted user" do
      @biz_org_admin.trade_controls_restriction.full!
      result = Repository.handle_creation(@biz_org_admin, @biz_org.login, { name: "internal-ofac", visibility: Repository::INTERNAL_VISIBILITY })
      refute_predicate result, :success
      assert_equal ::TradeControls::Notices.user_account_restricted, result.error_message
    end
  end

  context "integration installations" do
    test "queues background to calculate installation rate limit" do
      installation = make_integration_installation(target: @user, permissions: { "metadata" => :read })
      assert_enqueued_jobs 1, only: UpdateIntegrationInstallationRateLimitJob do
        perform_enqueued_hydro_jobs(only: [HydroAppsRepositoryCreatedJob], allowed_primary_query_count: 1) do
          perform_enqueued_jobs only: [RepositoryOrchestrationJob] do
            result = create_repository(owner: @user.login)
          end
        end
      end
    end
  end

  context "run_workspace_created_job step" do
    test "enqueues a WorkspaceCreatedJob to add an event to the timeline", skip_enterprise: true do
      @author = create(:user)
      @repo = create(:org_owned_repository, owner: @author)
      example_repo :simple, @repo
      @advisory = create(:repository_advisory, repository: @repo, author: @author)
      enable_feature_flag(:advisory_db_unrestorable_repositories, @advisory.repository)

      GitHub.context.push(actor_id: @author.id) # Avoids `ActiveRecord::RecordInvalid: Validation failed: Updater must exist`
      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        result = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
          RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(@advisory, @author)
        end

        message = {
          actor_id: @author.id,
          repository_id: @advisory.workspace_repository.id,
          advisory_id: @advisory.id,
        }

        assert_hydro_messages(count: 1, schema: "github.repositories.v1.WorkspaceCreated")
        assert_hydro_published(message, schema: "github.repositories.v1.WorkspaceCreated")
      end
    end
  end

  context "instruments" do
    test "creation" do
      events = subscribe "repo.create"
      repo = create_repository(owner: @user.login)

      expected_payload = {
        repo: repo.repository.name_with_owner,
        repo_id: repo.repository.id,
        public_repo: repo.repository.public?,
        fork_source: repo.repository.name_with_owner,
        fork_source_id: repo.repository.id,
        user: @user.login,
        user_id: @user.id,
        actor: @user.login,
        actor_id: @user.id,
        visibility: :public,
      }

      assert event = events.pop, "not instrumented"
      assert_equal "repo.create", event.name
      assert_equal expected_payload, event.payload
    end

    test "creates RepositoryCreate hydro event" do
      GitHub.stubs(:hydro_enabled?).returns(true)
      now = Time.now.beginning_of_day

      Timecop.freeze(now) do
        GitHub.context.push(actor_ip: "1.2.3.4")
        GitHub.context.push(user_agent: "test agent")

        repo = create_repository(owner: @user.login).repository

        serialized_repository = Hydro::EntitySerializer.repository(repo)

        message = {
          actor: Hydro::EntitySerializer.user(@user),
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository: serialized_repository,
          owner: Hydro::EntitySerializer.user(repo.owner),
        }

        assert_hydro_published(message, schema: "github.v1.RepositoryCreate")
      end
    end
  end

  context "repository projects disabled for organization" do
    test "successfully creates a repository if has_projects not specified" do
      # See https://github.com/github/github/issues/114982
      @org.disable_repository_projects(actor: @org.admin)
      refute_predicate @org.reload, :repository_projects_enabled?

      result = create_repository(user: @org.admin, owner: @org.login)
      assert_predicate result, :success?
    end

    test "fails to create a repository if has_projects is true and projects disabled" do
      @org.disable_repository_projects(actor: @org.admin)
      @org.disable_organization_projects(actor: @org.admin)
      refute_predicate @org.reload, :repository_projects_enabled?

      result = create_repository(user: @org.admin, owner: @org.login, has_projects: true)
      refute_predicate result, :success?
    end

    test "successfully creates a repository when projects are disabled if has_projects is false" do
      GitHub.context.push(actor_id: @org.admin.id)
      @org.disable_repository_projects(actor: @org.admin)
      @org.disable_organization_projects(actor: @org.admin)
      refute_predicate @org.reload, :repository_projects_enabled?

      result = create_repository(user: @org.admin, owner: @org.login, has_projects: false)
      assert_predicate result, :success?
      refute_predicate result.repository, :repository_projects_enabled?
      refute_predicate result.repository, :repository_memex_projects_enabled?
    end

    test "acquires a namespace lock during repository creation" do
      orchestration = RepositoryOrchestration.create_repository(
        actor: @user,
        owner_login: @user.name,
        repo_attributes: { name: "happy", owner: @user },
      )

      assert Repositories::RepositoryOwnerLock.locked_for_rename?(owner_id: @user.id)
    end

    test "releases a namespace lock after repository creation" do
      result = create_repository(owner: @user.login)

      assert_predicate result, :success?
      refute Repositories::RepositoryOwnerLock.locked_for_rename?(owner_id: @user.id)
    end

    test "successfully creates a repository if projects are not disabled" do
      assert_predicate @org, :repository_projects_enabled?

      result = create_repository(user: @org.admin, owner: @org.login, has_projects: true)
      assert_predicate result, :success?
    end
  end

  context "has_discussions" do
    test "successfully creates a repository without discussions if has_discussions not specified" do
      result = create_repository(owner: @user.login)
      assert_predicate result, :success?
      refute_predicate result.repository, :discussions_active?
    end

    test "successfully creates a repository without discussions if has_discussions is false" do
      result = create_repository(owner: @user.login, has_discussions: false)
      assert_predicate result, :success?
      refute_predicate result.repository, :discussions_active?
    end

    test "successfully creates a repository with discussions if has_discussions is true" do
      result = create_repository(owner: @user.login, has_discussions: true)
      assert_predicate result, :success?
      assert_predicate result.repository, :discussions_active?
    end
  end

  context "tiered_reporting" do
    if GitHub.enterprise?
      test "successfully creates a repository without tiered reporting enabled if owned by user and public" do
        result = create_repository(user: @org.admin, owner: @org.login)
        assert_predicate result, :success?
        refute_predicate result.repository, :tiered_reporting_explicitly_enabled?
      end
    else
      test "creates a repository with tiered reporting enabled if owned by organization and public" do
        result = create_repository(user: @org.admin, owner: @org.login)
        assert_predicate result, :success?
        assert_predicate result.repository, :tiered_reporting_explicitly_enabled?
      end

      test "creates a repository without tiered reporting if repository is private" do
        result = create_repository(user: @org.admin, owner: @org.login, private: true)
        assert_predicate result, :success?
        refute_predicate result.repository, :tiered_reporting_explicitly_enabled?
      end

      test "creates a repository without tiered reporting if repository is owned by a user" do
        result = create_repository(owner: @user.login)
        assert_predicate result, :success?
        refute_predicate result.repository, :tiered_reporting_explicitly_enabled?
      end
    end
  end

  context "dgit" do
    test "creates repository and network replicas" do
      run_dgit_replica_allocation_test \
        expected_count: GitHub.dgit_default_copies
    end

    test "creates repository and network with non-voting replicas" do
      non_voting_hosts = (1..2).map { DGit.add_fileserver(voting: false) }
      GitHub.dgit_non_voting_copies = 2

      run_dgit_replica_allocation_test \
        expected_count: 2 + GitHub.dgit_default_copies,
        expected_hosts: non_voting_hosts
    end

    test "create repository/network without non-voting replicas when they are all offline" do
      non_voting_hosts = (1..2).map { DGit.add_fileserver(voting: false, online: false) }
      GitHub.dgit_non_voting_copies = 2

      run_dgit_replica_allocation_test \
        expected_count: GitHub.dgit_default_copies,
        unexpected_hosts: non_voting_hosts
    end

    test "create repository/network without non-voting replicas when they are all embargoed" do
      non_voting_hosts = (1..2).map { DGit.add_fileserver(voting: false, embargoed: true) }
      GitHub.dgit_non_voting_copies = 2

      run_dgit_replica_allocation_test \
        expected_count: GitHub.dgit_default_copies,
        unexpected_hosts: non_voting_hosts
    end

    test "create repository/network with not enough non-voting replicas when there aren't enough" do
      non_voting_host = DGit.add_fileserver(voting: false)
      GitHub.dgit_non_voting_copies = 2

      run_dgit_replica_allocation_test \
        expected_count: GitHub.dgit_default_copies + 1,
        expected_hosts: [non_voting_host]
    end

    test "create repository/network without non-voting replicas when there aren't any non-voting fileservers" do
      GitHub.dgit_non_voting_copies = 2

      run_dgit_replica_allocation_test \
        expected_count: GitHub.dgit_default_copies
    end

    test "creates repository replicas and disk exactly once" do
      Repository::SpokesClientFacade.any_instance.expects(:create_repository).once
      Repository.any_instance.expects(:initialize_replicas_from_network).never
      Repository.any_instance.expects(:setup_git_repository).never

      create_repository(owner: @user.login)
    end
  end

  test "should publish Created event" do
    with_hydro_publisher(GitHub.sync_hydro_publisher) do

      result = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        create_repository(owner: @user.login)
      end

      assert result.success?

      assert_hydro_messages(count: 1, schema: "github.repositories.v1.Created")
      message = CreateRepositoryOrchestration.build_hydro_event_message(result.repository.id).merge({
        repository: Hydro::EntitySerializer.repository(result.repository),
        actor_id: @user.id
      })
      assert_hydro_published(message, schema: "github.repositories.v1.Created")
    end
  end

  test "raises on creations which do not use orchestration" do
    # Create a repo without going through the orchestration
    Rails.env.stubs(:production?).returns(true)

    assert_no_difference -> { Repository.count } do
      assert_raises Repository::RepoCreationOutsideOrchestration do
        @org.repositories.create! name: "foo"
      end
    end
  end

  test "succeeds when no rulesets are violated" do
    enable_feature_flag(:member_privilege_rulesets)

    ruleset = create(:repository_ruleset, :repository_policy, source: @biz_org)
    create(:repository_rule_configuration, :repository_visibility, repository_ruleset: ruleset)

    result = create_repository({
      owner: @biz_org.login,
      user: @biz_org_admin,
      name: "snowflake",
      public: false,
    })

    assert result.success?
    assert result.repository.persisted?
  end

  test "fails when ruleset is violated" do
    enable_feature_flag(:member_privilege_rulesets)

    ruleset = create(:repository_ruleset, :repository_policy, source: @biz_org)
    create(:repository_rule_configuration, :repository_visibility, public: false, internal: false, repository_ruleset: ruleset)

    result = create_repository({
      owner: @biz_org.login,
      user: @biz_org_admin,
      name: "snowflake",
      visibility: Repository::INTERNAL_VISIBILITY
    })

    refute result.success?
    refute result.repository.persisted?

    assert_empty CreateRepositoryOrchestration.all
  end

  test "fails when ruleset targeted by properties is violated" do
    enable_feature_flag(:member_privilege_rulesets)
    create :custom_property_definition, source: @biz_org, property_name: "env"

    ruleset = create(:repository_ruleset, target: "repository", source: @biz_org)
    create(:repository_rule_configuration, :repository_visibility, repository_ruleset: ruleset)
    create(:repository_rule_condition, repository_ruleset: ruleset, target: "repository_property", parameters: {
      "include": [{ "name": "env", "property_values": ["prod"] }],
      "exclude": [],
    })

    result = create_repository({
      owner: @biz_org.login,
      user: @biz_org_admin,
      name: "snowflake",
      public: true,
      custom_properties: { "env" => "prod" }
    })

    refute result.success?
    refute result.repository.persisted?

    assert_empty CreateRepositoryOrchestration.all
  end

  test "sends hard limit email" do
    create(:public_repository, owner: @user, force_user_owned: true)
    count = Repository.where(owner: @user).active.count
    limiter = RepositoryLimit.new(@user)
    limiter.override(soft: count, hard: count + 1)
    ActionMailer::Base.deliveries.clear

    result = perform_enqueued_jobs(only: [RepositoryOrchestrationJob, ApplicationDeliveryJob]) do
      create_repository(owner: @user.login)
    end
    assert result.success?

    if limiter.enabled?
      assert_equal 1, ActionMailer::Base.deliveries.size
      assert_equal "Repository limit reached for #{@user.display_login}", ActionMailer::Base.deliveries.first.subject
    else
      assert_equal 0, ActionMailer::Base.deliveries.size
    end
  end

  test "sends soft limit email" do
    create(:public_repository, owner: @user, force_user_owned: true)
    count = Repository.where(owner: @user).active.count
    limiter = RepositoryLimit.new(@user)
    ActionMailer::Base.deliveries.clear

    result = perform_enqueued_jobs(only: [RepositoryOrchestrationJob, ApplicationDeliveryJob]) do
      stub_const(RepositoryLimit, :SOFT_LIMIT, count + 1) do
        create_repository(owner: @user.login)
      end
    end
    assert result.success?

    if limiter.enabled?
      assert_equal 1, ActionMailer::Base.deliveries.size
      assert_equal "Approaching repository limit for #{@user.display_login}", ActionMailer::Base.deliveries.first.subject
    else
      assert_equal 0, ActionMailer::Base.deliveries.size
    end
  end

  test "delete respoitory_redirect on creation" do
    repo = create(:repository)
    create(:repository_redirect, repository: repo, repository_name: "#{@user.login}/repo")

    assert RepositoryRedirect.exists?(repository_name: "#{@user.login}/repo")

    result = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      create_repository(owner: @user.login, name: "repo")
    end

    assert result.success?

    refute RepositoryRedirect.exists?(repository_name: "#{@user.login}/repo")
  end

  def run_dgit_replica_allocation_test(expected_count:, expected_hosts: [], unexpected_hosts: [])
    # Mock picked fileservers because we can't change the placer policy in spokesd
    hosts = GitHub::Spokes.client.pick_fileservers(actor: @user).map { |fs| fs.name }
    hosts += expected_hosts
    GitHub::Spokes::Client.any_instance.expects(:pick_fileservers).once.returns(
      ::DGit::get_raw_fileservers.select do |fs|
        hosts.include?(fs.name)
      end)

    result = create_repository(owner: @user.login)
    assert result.success?
    repo = result.repository

    repo_replicas = GitHub::DGit::Routing.all_repo_replicas(repo.id, false)
    network_replicas = GitHub::DGit::Routing.all_network_replicas(repo.network_id)

    assert_equal expected_count, repo_replicas.size, "number of repository replicas"
    assert_equal expected_count, network_replicas.size, "number of network replicas"

    repo_replicas.each do |rep|
      assert_equal true, rep.healthy?, "replica is healthy"
    end

    repo_replica_hosts = repo_replicas.map(&:host)
    assert_same_elements repo_replica_hosts, network_replicas.map(&:host), "replicas are on the same hosts"
    expected_hosts.each do |host|
      assert_includes repo_replica_hosts, host, "expected a replica on this host"
    end
    unexpected_hosts.each do |host|
      refute_includes repo_replica_hosts, host, "did not expect a replica on this host"
    end

    repo
  end
end

class RepositoryCreatorToRestrictPersonalNamespaceEMUTest < GitHub::TestCase
  fixtures do
    @emu = create(:emu)
    @emu_business = @emu.enterprise_managed_business
    @emu_owner = @emu_business.owners.first
  end

  def create_repository_for_enterprise(params = {}, repo_class = Repository)
    repo_params = {
      name: "reponame",
      description: "an description",
      public: false, # since public repos are not allowed for EMUs
      user: @emu_owner
    }.merge(params)

    repo_params.delete(:public) if repo_params.key?(:visibility)

    owner = repo_params.delete(:owner)
    billing = repo_params.delete(:billing)
    user = repo_params.delete(:user)

    repo_class.handle_creation(
      user,
      owner,
      repo_params,
      reflog_data = {},
      billing,
    )
  end

  test "disables creation with enterprise setting enabled", skip_enterprise: true do
    @emu_business.enable_restrict_create_repository_in_personal_namespace(force: false, actor: @emu_owner)
    result = create_repository_for_enterprise(user: @emu_owner, owner: @emu_owner.login)

    refute result.success?
  end

  test "enables creation with enterprise setting disabled", skip_enterprise: true do
    @emu_business.disable_restrict_create_repository_in_personal_namespace(force: false, actor: @emu_owner)
    result = create_repository_for_enterprise(user: @emu_owner, owner: @emu_owner.login)

    assert result.success?
  end
end

class RepositoryCreatorToRestrictPersonalNamespaceGHESTest < GitHub::TestCase
  fixtures do
    if GitHub.enterprise?
      @enterprise_admin = create(:user)
      @enterprise_user = create(:user)
      @enterprise_org = create(:organization, plan: GitHub::Plan.enterprise, admins: [@enterprise_admin])
      @enterprise_business = create(:business, owners: [@enterprise_admin], organizations: [@enterprise_org])
      @enterprise_org.add_member(@enterprise_user)
    end
  end

  def create_repository_for_enterprise(params = {}, repo_class = Repository)
    repo_params = {
      name: "reponame",
      description: "an description",
      public: false,
      user:  @enterprise_admin
    }.merge(params)

    repo_params.delete(:public) if repo_params.key?(:visibility)

    owner = repo_params.delete(:owner)
    billing = repo_params.delete(:billing)
    user = repo_params.delete(:user)

    repo_class.handle_creation(
      user,
      owner,
      repo_params,
      reflog_data = {},
      billing,
    )
  end

  if GitHub.single_business_environment?
    test "disables creation with enterprise setting enabled" do
      @enterprise_business.enable_restrict_create_repository_in_personal_namespace(force: false, actor: @enterprise_admin)
      result = create_repository_for_enterprise(user: @enterprise_user, owner: @enterprise_user.login)

      refute result.success?
    end

    test "enables creation with enterprise setting disabled" do
      @enterprise_business.disable_restrict_create_repository_in_personal_namespace(force: false, actor: @enterprise_admin)
      result = create_repository_for_enterprise(user: @enterprise_user, owner: @enterprise_user.login)

      assert result.success?
    end
  end
end
