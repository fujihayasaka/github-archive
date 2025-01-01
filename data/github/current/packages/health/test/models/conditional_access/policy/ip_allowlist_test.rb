# typed: true
# frozen_string_literal: true

require "test_helper"

class IPTestCallback
  def action
    nil
  end
end

class TestIpAllowlistPolicy
  include ConditionalAccess::Policy::IpAllowlist

  attr_reader :target_provider

  def initialize(
    targets: nil,
    resource: nil,
    target: nil,
    actor_ip: nil,
    repository: nil,
    action: nil,
    actor: nil,
    public_key: nil
  )
    @targets = targets
    @resource = resource
    @target = target
    @actor_ip = actor_ip
    @repository = repository
    @action = action
    self.callback.stubs(:action).returns(@action)
    @actor = actor
    @public_key = public_key
    @target_provider = ConditionalAccess::TargetProvider.new(location: :test, callback_name: "IPTestCallback")
  end

  def targets
    @targets
  end

  def resource
    @resource
  end

  def target
    @target
  end

  def actor_ip
    @actor_ip
  end

  def repository
    @repository
  end

  def action
    @action
  end

  def actor
    @actor
  end

  def public_key
    @public_key
  end

  def anonymous?
    !@actor
  end

  def callback
    IPTestCallback.new
  end
end

class CapIpAllowlistPolicyBaseTest < GitHub::TestCase
  def self.no_actor
    [0]
  end

  def self.rando_actor
    [1]
  end

  def self.no_repo_access_actor
    [3]
  end

  def self.integration_installation_actor
    [5]
  end

  def self.guest_collaborator
    [5]
  end

  def self.repository_collaborator
    [6]
  end

  def self.test_actions
    [nil, :read, :write]
  end

  def self.description_of(action)
    action || "nil"
  end

  sig do
    params(
      actors: T::Array[Integer],
      name: String,
      block: T.proc.bind(CapIpAllowlistPolicyTest).void
    ).void
  end
  def self.test_with_actors(actors, name, &block)
    test_actor_context_names = [
      "without actor",
      "with actor",
      "with member actor",
      "with member without repo access actor",
      "with outside collaborator actor",
      "with installed integration",
      "with integration",
    ]
    actors.each do |a|
      test_block = proc do
        @actor = @actors[a]
        instance_eval &block
      end
      test "#{test_actor_context_names[a]} #{name}", &test_block
    end
  end

  sig do
    params(
      name: String,
      block: T.proc.bind(CapIpAllowlistPolicyTest).void
    ).void
  end
  def self.test_with_all_user_actors(name, &block)
    test_with_actors([0, 1, 2, 3, 4], name, &block)
  end

  sig do
    params(
      name: String,
      block: T.proc.bind(CapIpAllowlistPolicyTest).void
    ).void
  end
  def self.test_with_integration_actors(name, &block)
    test_with_actors([5, 6], name, &block)
  end

  sig do
    params(
      name: String,
      block: T.proc.bind(CapIpAllowlistPolicyTest).void
    ).void
  end
  def self.test_with_all_actors(name, &block)
    test_with_actors([0, 1, 2, 3, 4, 5, 6], name, &block)
  end

  sig do
    params(
      actors: T::Array[Integer],
      name: String,
      block: T.proc.bind(CapIpAllowlistPolicyTest).void
    ).void
  end
  def self.test_with_actors_except(actors, name, &block)
    test_with_actors([0, 1, 2, 3, 4, 5, 6] - actors, name, &block)
  end

  sig do
    params(
      actors: T::Array[Integer],
      name: String,
      block: T.proc.bind(CapIpAllowlistPolicyTest).void
    ).void
  end
  def self.test_with_emu_actors(actors, name, &block)
    test_actor_context_names = [
      "without actor",
      "with actor",
      "with member actor",
      "with installed integration",
      "with integration",
      "with guest collaborator actor",
      "with repository collaborator actor",
    ]
    actors.each do |a|
      test_block = proc do
        @actor = @emu_actors[a]
        instance_eval &block
      end
      test "#{test_actor_context_names[a]} #{name}", &test_block
    end
  end

  sig do
    params(
      name: String,
      block: T.proc.bind(CapIpAllowlistPolicyTest).void
    ).void
  end
  def self.test_with_all_emu_user_actors(name, &block)
    test_with_emu_actors([0, 1, 2, 5, 6], name, &block)
  end

  sig do
    params(
      name: String,
      block: T.proc.bind(CapIpAllowlistPolicyTest).void
    ).void
  end
  def self.test_with_emu_integration_actors(name, &block)
    test_with_actors([3, 4], name, &block)
  end

  sig do
    params(
      name: String,
      block: T.proc.bind(CapIpAllowlistPolicyTest).void
    ).void
  end
  def self.test_with_all_emu_actors(name, &block)
    test_with_emu_actors([0, 1, 2, 3, 4, 5, 6], name, &block)
  end

  sig do
    params(
      actors: T::Array[Integer],
      name: String,
      block: T.proc.bind(CapIpAllowlistPolicyTest).void
    ).void
  end
  def self.test_with_emu_actors_except(actors, name, &block)
    test_with_emu_actors([0, 1, 2, 3, 4, 5, 6] - actors, name, &block)
  end

  def init_actor_installation(installation)
    @actor.installation = installation if @actor.respond_to?(:installation=)
  end

  def actor_payload(actor)
    if actor.is_a?(Integration)
      { integration_actor: Hydro::EntitySerializer.integration(actor) }
    else
      { actor: Hydro::EntitySerializer.user(actor) }
    end
  end

  def assert_policy_applicable(policy, msg = nil)
    result = policy.ip_allowlist_applicable(resource: policy.resource || policy.target, target_provider: policy.target_provider)
    msg = message(msg) { "Expected #ip_allowlist_applicable to be :yes" }
    assert_equal :yes, result, msg
  end

  def refute_policy_applicable(policy, msg = nil)
    result = policy.ip_allowlist_applicable(resource: policy.resource || policy.target, target_provider: policy.target_provider)
    msg = message(msg) { "Expected #ip_allowlist_applicable to be :no" }
    assert_equal :no, result, msg
  end

  def assert_policy_satisfied(policy, msg = nil)
    result = policy.ip_allowlist_satisfied(resource: policy.resource || policy.target, target_provider: policy.target_provider)
    msg = message(msg) { "Expected #ip_allowlist_satisfied to be :yes" }
    assert_equal :yes, result, msg
  end

  def refute_policy_satisfied(policy, msg = nil)
    result = policy.ip_allowlist_satisfied(resource: policy.resource || policy.target, target_provider: policy.target_provider)
    msg = message(msg) { "Expected #ip_allowlist_satisfied to be :no" }
    assert_equal :no, result, msg
  end
end

class CapIpAllowlistPolicyTest < CapIpAllowlistPolicyBaseTest
  include HydroTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    @rando = create :user, login: "rando"
    @member = create :user, login: "member"
    @member_without_repo_access = create :user, login: "member-without-repo-access"
    @collaborator = create :user, login: "collaborator"
    @integration = create :integration
    @integration_bot = @integration.bot
    @allowed_ip = "10.10.10.10"
    @allowed_ip_range = "10.10.10.0/24"
    @allowed_integration_ip = "20.20.20.20"
    @allowed_integration_ip_range = "20.20.20.0/24"
    @denied_ip = "1.1.1.1"
    @denied_ip_range = "1.1.1.0/24"

    if GitHub.ip_allowlists_available?
      create :ip_allowlist_entry, owner: @integration, active: true, allow_list_value: @allowed_ip_range
      create :ip_allowlist_entry, owner: @integration, active: true, allow_list_value: @allowed_integration_ip_range

      @org = create :business_plus_org
      perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { @org.update_default_repository_permission(:none, actor: @org.admins.first) }
      team = create(:team, organization: @org)
      team.add_member @member
      @org.add_member @member_without_repo_access
      @repo = create(:private_repository, :minimal, owner: @org)
      team.add_repository @repo, :admin
      @repo.add_member @collaborator
      @public_repo = create(:public_repository, :minimal, owner: @org)
      @public_repo.add_member @collaborator
      @org.enable_ip_allowlist actor: @org.admins.first
      @org.enable_ip_allowlist_app_access actor: @org.admins.first
      create :ip_allowlist_entry, owner: @org, active: true, allow_list_value: @allowed_ip_range
      @org_install = make_integration_installation target: @org, integration: @integration
      @user_install = make_integration_installation target: @member, integration: @integration

      @business = create :business
      @business.enable_ip_allowlist actor: @business.owners.first
      @business.enable_ip_allowlist_app_access actor: @business.owners.first
      create :ip_allowlist_entry, owner: @business, active: true, allow_list_value: @allowed_ip_range
      @binstall = make_integration_installation(target: @business, integration: @integration, permissions: { Business::Resources.subject_types.first => :read })

      @borg = create :business_plus_org
      perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { @borg.update_default_repository_permission(:none, actor: @borg.admins.first) }
      @borg2 = create :business_plus_org
      if GitHub.single_business_environment?
        @bbusiness = GitHub.global_business
        @bbusiness.add_organization(@borg)
        @bbusiness.add_organization(@borg2)
      else
        @bbusiness = create :business, organizations: [@borg, @borg2]
      end
      bteam = create(:team, organization: @borg)
      bteam.add_member @member
      @borg.add_member @member_without_repo_access
      @brepo = create(:private_repository, :minimal, owner: @borg)
      bteam.add_repository @brepo, :admin
      @brepo.add_member @collaborator
      @bpublic_repo = create(:public_repository, :minimal, owner: @borg)
      @borg2_member = create :user
      @borg2.add_member @borg2_member
      @borg2.reload
      @internal_repo = create :internal_repository, owner: @borg2
      @internal_repo.add_member @collaborator
      @bbusiness.enable_ip_allowlist actor: @bbusiness.owners.first
      @bbusiness.enable_ip_allowlist_app_access actor: @bbusiness.owners.first
      create :ip_allowlist_entry, owner: @bbusiness, active: true, allow_list_value: @allowed_ip_range
      create :ip_allowlist_entry, owner: @borg, active: true, allow_list_value: @allowed_ip_range
      @borg.reload
      @borg_install = make_integration_installation target: @borg, integration: @integration
      @borg2_install = make_integration_installation target: @borg2, integration: @integration
    end
  end

  setup do
    @actors = [
      nil,
      @rando,
      @member,
      @member_without_repo_access,
      @collaborator,
      @integration_bot,
      @integration,
    ]
  end

  context "#multiple_ip_allowlist_applicable" do
    if GitHub.ip_allowlists_available?
      test "returns only applicable targets" do
        policy = TestIpAllowlistPolicy.new targets: [@org, @member, @repo, :no_target_for_conditional_access]
        assert_runs_sql_queries(total: 0) do
          result = policy.multiple_ip_allowlist_applicable(policy.targets, policy.target_provider)
          assert_equal [@org], result, "Expected #multiple_ip_allowlist_applicable to return applicable targets"
        end
      end

      test "includs EMUs (Enterprise Managed Users)" do
        emu = create :emu
        policy = TestIpAllowlistPolicy.new targets: [@org, @member, @repo, emu, :no_target_for_conditional_access]
        assert_runs_sql_queries(total: 0) do
          result = policy.multiple_ip_allowlist_applicable(policy.targets, policy.target_provider)
          assert_equal [@org, emu], result, "Expected #multiple_ip_allowlist_applicable to return applicable targets"
        end
      end
    else
      test "returns empty when IP allow lists are not available" do
        policy = TestIpAllowlistPolicy.new targets: [@org, @member, @repo, :no_target_for_conditional_access]
        assert_runs_sql_queries(total: 0) do
          result = policy.multiple_ip_allowlist_applicable(policy.targets, policy.target_provider)
          assert_equal [], result, "Expected #multiple_ip_allowlist_applicable to be empty"
        end
      end
    end
  end

  context "#multiple_ip_allowlist_satisfied" do
    if GitHub.ip_allowlists_available?
      test "does not return targets where IP is not allowed" do
        policy = TestIpAllowlistPolicy.new targets: [@org], actor: @member, actor_ip: @denied_ip
        queries = assert_runs_sql_queries do
          result = policy.multiple_ip_allowlist_satisfied(policy.targets, policy.target_provider)
          assert_equal({ @org => { private: :unsatisfied } }, result)
        end
        assert_equal 11, queries.count { |q| q[:sql] !~ /flipper/ }
      end

      test "returns only targets where IP is allowed" do
        another_org = create :business_plus_org
        another_org.add_member @member
        create :ip_allowlist_entry, owner: another_org, active: true, allow_list_value: "4.3.2.1"
        another_org.enable_ip_allowlist actor: another_org.admins.first

        policy = TestIpAllowlistPolicy.new targets: [@org, another_org], actor: @member, actor_ip: @allowed_ip
        queries = assert_runs_sql_queries do
          result = policy.multiple_ip_allowlist_satisfied(policy.targets, policy.target_provider)
          assert_equal({ another_org => { private: :unsatisfied }, @org => { private: :satisfied } }, result)
        end
        assert_equal 11, queries.count { |q| q[:sql] !~ /flipper/ }
      end
    end
  end

  context "#ip_allowlist_applicable" do
    if GitHub.ip_allowlists_available?
      test "returns :no when target is :no_target_for_conditional_access" do
        policy = TestIpAllowlistPolicy.new target: :no_target_for_conditional_access, actor: @actor
        refute_policy_applicable policy
      end

      test "returns :no when target type is inapplicable" do
        policy = TestIpAllowlistPolicy.new target: create(:repository)
        refute_policy_applicable policy
      end

      test "returns :no when actor is nil" do
        policy = TestIpAllowlistPolicy.new target: @org, actor: nil
        refute_policy_applicable policy
      end

      test "returns :no when actor and public_key are nil" do
        policy = TestIpAllowlistPolicy.new target: @org, actor: nil, public_key: nil
        refute_policy_applicable policy
      end

      test "returns :no when IP allow list disabled on target" do
        @org.disable_ip_allowlist actor: @org.admins.first
        policy = TestIpAllowlistPolicy.new target: @org, actor: @member
        refute_policy_applicable policy
      end

      test "returns :yes when IP allow list enabled and actor provided" do
        policy = TestIpAllowlistPolicy.new target: @org, actor: @member
        assert_policy_applicable policy
      end

      test "returns :yes when IP allow list enabled and public_key provided" do
        policy = TestIpAllowlistPolicy.new target: @org, public_key: create(:public_key, user: @member)
        assert_policy_applicable policy
      end

      test "returns :no when target is regular user" do
        user = create :user
        policy = TestIpAllowlistPolicy.new target: user, actor: user
        refute_policy_applicable policy
      end

      test "returns :no when target is EMU user and IP allow list disabled and not configured" do
        emu = create :emu
        policy = TestIpAllowlistPolicy.new target: emu, actor: emu
        refute_policy_applicable policy
      end

      test "returns :no when target is EMU user, IP allow list enabled, and user-level enforcement disabled" do
        emu = create :emu
        emu_business = emu.enterprise_managed_business
        emu_business.enable_ip_allowlist actor: emu_business.owners.first
        refute_predicate emu_business, :ip_allowlist_user_level_enforcement_enabled?

        policy = TestIpAllowlistPolicy.new target: emu, actor: emu

        refute_policy_applicable policy
      end

      test "returns :no when target is EMU user, IP allow list enabled, and user-level enforcement enabled, without ip_allowlist_user_level_enforcement enabled" do
        emu = create :emu
        emu_business = emu.enterprise_managed_business
        disable_feature_flag(:ip_allowlist_user_level_enforcement, emu_business)
        emu_business.enable_ip_allowlist actor: emu_business.owners.first
        emu_business.enable_ip_allowlist_user_level_enforcement actor: emu_business.owners.first
        refute_predicate emu_business, :ip_allowlist_user_level_enforcement_enabled?

        policy = TestIpAllowlistPolicy.new target: emu, actor: emu

        refute_policy_applicable policy
      end

      test "returns :no when target is EMU user, IP allow list configured but not enabled, and user-level enforcement enabled, with ip_allowlist_user_level_enforcement enabled" do
        emu = create :emu
        emu_business = emu.enterprise_managed_business
        enable_feature_flag(:ip_allowlist_user_level_enforcement, emu_business)
        create :ip_allowlist_entry, owner: emu_business
        emu_business.disable_ip_allowlist actor: emu_business.owners.first
        emu_business.enable_ip_allowlist_user_level_enforcement actor: emu_business.owners.first
        assert_predicate emu_business, :ip_allowlist_user_level_enforcement_enabled?

        policy = TestIpAllowlistPolicy.new target: emu, actor: emu

        refute_policy_applicable policy
      end

      test "returns :yes when target is EMU user, IP allow list configured and enabled, and user-level enforcement enabled, with ip_allowlist_user_level_enforcement enabled" do
        emu = create :emu
        emu_business = emu.enterprise_managed_business
        enable_feature_flag(:ip_allowlist_user_level_enforcement, emu_business)
        create :ip_allowlist_entry, owner: emu_business
        emu_business.enable_ip_allowlist actor: emu_business.owners.first
        emu_business.enable_ip_allowlist_user_level_enforcement actor: emu_business.owners.first
        assert_predicate emu_business, :ip_allowlist_user_level_enforcement_enabled?

        policy = TestIpAllowlistPolicy.new target: emu, actor: emu

        assert_policy_applicable policy
      end
    else
      test "returns :no when IP allow lists are not available" do
        policy = TestIpAllowlistPolicy.new
        refute_policy_applicable policy
      end
    end
  end

  context "#ip_allowlist_satisfied" do
    if GitHub.ip_allowlists_available?
      test "returns :yes when target is :no_target_for_conditional_access" do
        init_actor_installation nil
        policy = TestIpAllowlistPolicy.new target: :no_target_for_conditional_access
        assert_policy_satisfied policy
      end

      test "returns :yes when target is a regular User" do
        init_actor_installation nil
        policy = TestIpAllowlistPolicy.new target: create(:user)
        assert_policy_satisfied policy
      end

      context "when target is Organization" do
        context "when IP allow list is enabled" do
          context "with no active entries" do
            test_with_all_user_actors "returns :yes" do
              init_actor_installation @org_install
              @org.ip_allowlist_entries.destroy_all
              create :ip_allowlist_entry, owner: @org, active: false
              policy = TestIpAllowlistPolicy.new target: @org, actor: @actor
              assert_policy_satisfied policy
            end

            test_with_integration_actors "returns :no" do
              init_actor_installation @org_install
              @org.ip_allowlist_entries.destroy_all
              create :ip_allowlist_entry, owner: @org, active: false
              policy = TestIpAllowlistPolicy.new target: @org, actor: @actor
              refute_policy_satisfied policy
            end
          end

          context "and IP allowed" do
            test_with_all_actors "returns :yes" do
              init_actor_installation @org_install
              policy = TestIpAllowlistPolicy.new target: @org, actor_ip: @allowed_ip, actor: @actor
              assert_policy_satisfied policy
            end

            test_with_integration_actors "returns :no with app access disabled on integration entry" do
              init_actor_installation @org_install
              @org.disable_ip_allowlist_app_access actor: @org.admin
              policy = TestIpAllowlistPolicy.new target: @org, actor_ip: @allowed_integration_ip, actor: @actor
              refute_policy_satisfied policy
            end

            test_with_integration_actors "returns :yes with app access disabled on regular entry" do
              init_actor_installation @org_install
              @org.disable_ip_allowlist_app_access actor: @org.admin
              policy = TestIpAllowlistPolicy.new target: @org, actor_ip: @allowed_ip, actor: @actor
              assert_policy_satisfied policy
            end

            test_with_integration_actors "returns :yes with user rule enabled" do
              init_actor_installation @org_install
              @integration.ip_allowlist_entries.destroy_all
              policy = TestIpAllowlistPolicy.new target: @org, actor_ip: @allowed_ip, actor: @actor
              assert_policy_satisfied policy
            end

            test "with installed integration on user returns :yes" do
              user = create :user
              installation = make_integration_installation target: user, integration: @integration
              actor = @integration.bot
              actor.installation = installation

              policy = TestIpAllowlistPolicy.new target: @org, actor_ip: @allowed_ip, actor: actor
              assert_policy_satisfied policy
            end
          end

          context "and IP denied" do
            test_with_actors rando_actor, "returns :yes" do
              init_actor_installation @org_install
              policy = TestIpAllowlistPolicy.new target: @org, actor_ip: @denied_ip, actor: @actor
              assert_policy_satisfied policy
            end

            test_with_actors_except no_actor + rando_actor, "returns :no" do
              init_actor_installation @org_install
              policy = TestIpAllowlistPolicy.new target: @org, actor_ip: @denied_ip, actor: @actor
              refute_policy_satisfied policy
            end

            test_with_actors_except no_actor + rando_actor, "publishes github.ip_allow_list.v0.PolicyUnsatisfied message to Hydro" do
              init_actor_installation @org_install
              policy = TestIpAllowlistPolicy.new target: @org, actor_ip: @denied_ip, actor: @actor
              refute_policy_satisfied policy

              expected_payload = {
                owner_type: :ORG,
                owner_id: @org.id,
                actor_ip: @denied_ip,
              }.update(actor_payload(@actor))
              assert_hydro_published(
                expected_payload,
                schema: "github.ip_allow_list.v0.PolicyUnsatisfied",
              )
              assert_hydro_messages(count: 1, schema: "github.ip_allow_list.v0.PolicyUnsatisfied")
            end
          end

          context "and IP matches custom hosted runner" do
            test_with_actors_except no_actor + rando_actor, "returns :no in dotcom" do
              GitHub.actions_runner_ip_ranges = [@denied_ip_range]
              init_actor_installation @org_install
              policy = TestIpAllowlistPolicy.new target: @org, actor_ip: @denied_ip, actor: @actor
              refute_policy_satisfied policy
            end
          end
        end

        context "when installed on user" do
          test_with_actors integration_installation_actor, "returns :yes" do
            init_actor_installation @user_install
            policy = TestIpAllowlistPolicy.new target: @member, actor: @actor
            assert_policy_satisfied policy
          end
        end

        context "repository is public" do
          context "when IP allowed" do
            test_actions.each do |action|
              test_with_all_actors "and action is #{action} returns :yes" do
                init_actor_installation @org_install
                policy = TestIpAllowlistPolicy.new target: @org, actor_ip: @allowed_ip, repository: @public_repo, action: action, actor: @actor
                assert_policy_satisfied policy
              end
            end
          end

          context "when IP denied" do
            context "but action is nil" do
              test_with_actors rando_actor, "returns :yes" do
                init_actor_installation @org_install
                policy = TestIpAllowlistPolicy.new target: @org, actor_ip: @denied_ip, repository: @public_repo, action: nil, actor: @actor
                assert_policy_satisfied policy
              end

              test_with_actors_except no_actor + rando_actor, "returns :no" do
                init_actor_installation @org_install
                policy = TestIpAllowlistPolicy.new target: @org, actor_ip: @denied_ip, repository: @public_repo, action: nil, actor: @actor
                refute_policy_satisfied policy
              end

              test_with_actors_except no_actor + rando_actor, "publishes github.ip_allow_list.v0.PolicyUnsatisfied message to Hydro" do
                init_actor_installation @org_install
                policy = TestIpAllowlistPolicy.new target: @org, actor_ip: @denied_ip, repository: @public_repo, action: nil, actor: @actor
                refute_policy_satisfied policy

                expected_payload = {
                  owner_type: :ORG,
                  owner_id: @org.id,
                  actor_ip: @denied_ip,
                }.update(actor_payload(@actor))
                assert_hydro_published(
                  expected_payload,
                  schema: "github.ip_allow_list.v0.PolicyUnsatisfied",
                )
                assert_hydro_messages(count: 1, schema: "github.ip_allow_list.v0.PolicyUnsatisfied")
              end
            end

            context "and action is :read" do
              test_with_all_actors "returns :yes" do
                init_actor_installation @org_install
                policy = TestIpAllowlistPolicy.new target: @org, actor_ip: @denied_ip, repository: @public_repo, action: :read, actor: @actor
                assert_policy_satisfied policy
              end
            end

            context "and action is :write" do
              test_with_actors rando_actor, "returns :yes" do
                init_actor_installation @org_install
                policy = TestIpAllowlistPolicy.new target: @org, actor_ip: @denied_ip, repository: @public_repo, action: :write, actor: @actor
                assert_policy_satisfied policy
              end

              test_with_actors_except no_actor + rando_actor, "returns :no" do
                init_actor_installation @org_install
                policy = TestIpAllowlistPolicy.new target: @org, actor_ip: @denied_ip, repository: @public_repo, action: :write, actor: @actor
                refute_policy_satisfied policy
              end

              test_with_actors_except no_actor + rando_actor, "publishes github.ip_allow_list.v0.PolicyUnsatisfied message to Hydro" do
                init_actor_installation @org_install
                policy = TestIpAllowlistPolicy.new target: @org, actor_ip: @denied_ip, repository: @public_repo, action: :write, actor: @actor
                refute_policy_satisfied policy

                expected_payload = {
                  owner_type: :ORG,
                  owner_id: @org.id,
                  actor_ip: @denied_ip,
                }.update(actor_payload(@actor))
                assert_hydro_published(
                  expected_payload,
                  schema: "github.ip_allow_list.v0.PolicyUnsatisfied",
                )
                assert_hydro_messages(count: 1, schema: "github.ip_allow_list.v0.PolicyUnsatisfied")
              end
            end
          end
        end

        context "repository is private" do
          context "when IP allowed" do
            test_actions.each do |action|
              test_with_all_actors "and action is #{description_of action} returns :yes" do
                init_actor_installation @org_install
                policy = TestIpAllowlistPolicy.new target: @org, actor_ip: @allowed_ip, repository: @repo, action: action, actor: @actor
                assert_policy_satisfied policy
              end
            end
          end

          context "when IP denied" do
            test_actions.each do |action|
              test_with_actors rando_actor, "and action is #{description_of action} returns :yes" do
                init_actor_installation @org_install
                policy = TestIpAllowlistPolicy.new target: @org, actor_ip: @denied_ip, repository: @repo, action: action, actor: @actor
                assert_policy_satisfied policy
              end

              test_with_actors_except no_actor + rando_actor + no_repo_access_actor, "and action is #{description_of action} returns :no" do
                init_actor_installation @org_install
                policy = TestIpAllowlistPolicy.new target: @org, actor_ip: @denied_ip, repository: @repo, action: action, actor: @actor
                refute_policy_satisfied policy
              end

              test_with_actors_except no_actor + rando_actor + no_repo_access_actor, "and action is #{description_of action} publishes github.ip_allow_list.v0.PolicyUnsatisfied message to Hydro" do
                init_actor_installation @org_install
                policy = TestIpAllowlistPolicy.new target: @org, actor_ip: @denied_ip, repository: @repo, action: action, actor: @actor
                refute_policy_satisfied policy

                expected_payload = {
                  owner_type: :ORG,
                  owner_id: @org.id,
                  actor_ip: @denied_ip,
                }.update(actor_payload(@actor))
                assert_hydro_published(
                  expected_payload,
                  schema: "github.ip_allow_list.v0.PolicyUnsatisfied",
                )
                assert_hydro_messages(count: 1, schema: "github.ip_allow_list.v0.PolicyUnsatisfied")
              end
            end
          end
        end
      end

      context "when target is business-owned Organization" do
        context "when IP allow list enabled on owning Business" do
          context "and IP allowed" do
            test_with_all_actors "returns :yes" do
              init_actor_installation @borg_install
              policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @allowed_ip, actor: @actor
              assert_policy_satisfied policy
            end

            test_with_integration_actors "returns :no with app access disabled on integration entry" do
              init_actor_installation @borg_install
              @bbusiness.disable_ip_allowlist_app_access actor: @bbusiness.owners.first
              policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @allowed_integration_ip, actor: @actor
              refute_policy_satisfied policy
            end

            test_with_integration_actors "returns :yes with app access disabled on regular entry" do
              init_actor_installation @borg_install
              @bbusiness.disable_ip_allowlist_app_access actor: @bbusiness.owners.first
              policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @allowed_ip, actor: @actor
              assert_policy_satisfied policy
            end

            test_with_integration_actors "returns :yes with user rule enabled" do
              init_actor_installation @borg_install
              @integration.ip_allowlist_entries.destroy_all
              policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @allowed_ip, actor: @actor
              assert_policy_satisfied policy
            end
          end

          context "and IP allowed at the org level but not at the business level" do
            test "returns :yes when owner is org" do
              init_actor_installation @borg_install
              org_admin = create :user
              org = create :business_plus_org, admin: org_admin
              org.disable_ip_allowlist actor: org_admin
              @business.add_organization org
              create :ip_allowlist_entry, owner: org, active: true, allow_list_value: "8.8.8.8/8"
              org.reload

              policy = TestIpAllowlistPolicy.new target: org, actor_ip: "8.8.8.8", actor: org_admin
              assert_policy_satisfied policy
            end

            test "returns :no when owner is business" do
              init_actor_installation @borg_install
              org_admin = create :user
              org = create :business_plus_org, admin: org_admin
              @business.add_organization org
              create :ip_allowlist_entry, owner: org, active: true, allow_list_value: "8.8.8.8/8"
              org.reload

              policy = TestIpAllowlistPolicy.new target: @business, actor_ip: "8.8.8.8", actor: org_admin
              refute_policy_satisfied policy
            end
          end

          context "and IP denied" do
            test_with_actors rando_actor, "returns :yes" do
              init_actor_installation @borg_install
              policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @denied_ip, actor: @actor
              assert_policy_satisfied policy
            end

            test_with_actors_except no_actor + rando_actor + no_repo_access_actor, "returns :no" do
              init_actor_installation @borg_install
              policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @denied_ip, actor: @actor
              refute_policy_satisfied policy
            end

            test "with member in other enterprise owned org returns :no" do
              skip if GitHub.single_business_environment?
              # @borg and @borg2 are owned by @bbusiness, @borg2_member is only a member of @borg2
              init_actor_installation @borg_install
              policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @denied_ip, actor: @borg2_member
              refute_policy_satisfied policy
            end

            test_with_actors_except no_actor + rando_actor + no_repo_access_actor, "publishes github.ip_allow_list.v0.PolicyUnsatisfied message to Hydro" do
              init_actor_installation @borg_install
              policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @denied_ip, actor: @actor
              refute_policy_satisfied policy

              expected_payload = {
                owner_type: :ORG,
                owner_id: @borg.id,
                actor_ip: @denied_ip,
              }.update(actor_payload(@actor))
              assert_hydro_published(
                expected_payload,
                schema: "github.ip_allow_list.v0.PolicyUnsatisfied",
              )
              assert_hydro_messages(count: 1, schema: "github.ip_allow_list.v0.PolicyUnsatisfied")
            end
          end
        end

        context "repository is public" do
          context "when IP allowed" do
            test_actions.each do |action|
              test_with_all_actors "and action is #{action} returns :yes" do
                init_actor_installation @borg_install
                policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @allowed_ip, repository: @bpublic_repo, action: action, actor: @actor
                assert_policy_satisfied policy
              end
            end
          end

          context "when IP denied" do
            context "but action is nil" do
              test_with_actors rando_actor, "returns :yes" do
                init_actor_installation @borg_install
                policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @denied_ip, repository: @bpublic_repo, action: nil, actor: @actor
                assert_policy_satisfied policy
              end

              test_with_actors_except no_actor + rando_actor, "returns :no" do
                init_actor_installation @borg_install
                policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @denied_ip, repository: @bpublic_repo, action: nil, actor: @actor
                refute_policy_satisfied policy
              end

              test_with_actors_except no_actor + rando_actor, "publishes github.ip_allow_list.v0.PolicyUnsatisfied message to Hydro" do
                init_actor_installation @borg_install
                policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @denied_ip, repository: @bpublic_repo, action: nil, actor: @actor
                refute_policy_satisfied policy

                expected_payload = {
                  owner_type: :ORG,
                  owner_id: @borg.id,
                  actor_ip: @denied_ip,
                }.update(actor_payload(@actor))
                assert_hydro_published(
                  expected_payload,
                  schema: "github.ip_allow_list.v0.PolicyUnsatisfied",
                )
                assert_hydro_messages(count: 1, schema: "github.ip_allow_list.v0.PolicyUnsatisfied")
              end
            end

            context "and action is :read" do
              test_with_all_actors "returns :yes" do
                init_actor_installation @borg_install
                policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @denied_ip, repository: @bpublic_repo, action: :read, actor: @actor
                assert_policy_satisfied policy
              end
            end

            context "and action is :write" do
              test_with_actors rando_actor, "returns :yes" do
                init_actor_installation @borg_install
                policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @denied_ip, repository: @bpublic_repo, action: :write, actor: @actor
                assert_policy_satisfied policy
              end

              test_with_actors_except no_actor + rando_actor, "returns :no" do
                init_actor_installation @borg_install
                policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @denied_ip, repository: @bpublic_repo, action: :write, actor: @actor
                refute_policy_satisfied policy
              end

              test_with_actors_except no_actor + rando_actor, "publishes github.ip_allow_list.v0.PolicyUnsatisfied message to Hydro" do
                init_actor_installation @borg_install
                policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @denied_ip, repository: @bpublic_repo, action: :write, actor: @actor
                refute_policy_satisfied policy

                expected_payload = {
                  owner_type: :ORG,
                  owner_id: @borg.id,
                  actor_ip: @denied_ip,
                }.update(actor_payload(@actor))
                assert_hydro_published(
                  expected_payload,
                  schema: "github.ip_allow_list.v0.PolicyUnsatisfied",
                )
                assert_hydro_messages(count: 1, schema: "github.ip_allow_list.v0.PolicyUnsatisfied")
              end
            end
          end
        end

        context "repository is internal" do
          context "when IP allowed" do
            test_actions.each do |action|
              test_with_all_actors "and action is #{description_of action} returns :yes" do
                init_actor_installation @borg2_install
                policy = TestIpAllowlistPolicy.new target: @borg2, actor_ip: @allowed_ip, repository: @internal_repo, action: action, actor: @actor
                assert_policy_satisfied policy
              end
            end
          end

          context "when IP denied" do
            test_actions.each do |action|
              test_with_actors_except no_actor, "and action is #{description_of action} returns :no" do
                init_actor_installation @borg2_install
                policy = TestIpAllowlistPolicy.new target: @borg2, actor_ip: @denied_ip, repository: @internal_repo, action: action, actor: @actor
                refute_policy_satisfied policy
              end

              test_with_actors_except no_actor + rando_actor, "and action is #{description_of action} publishes github.ip_allow_list.v0.PolicyUnsatisfied message to Hydro" do
                init_actor_installation @borg2_install
                policy = TestIpAllowlistPolicy.new target: @borg2, actor_ip: @denied_ip, repository: @internal_repo, action: action, actor: @actor
                refute_policy_satisfied policy

                expected_payload = {
                  owner_type: :ORG,
                  owner_id: @borg2.id,
                  actor_ip: @denied_ip,
                }.update(actor_payload(@actor))
                assert_hydro_published(
                  expected_payload,
                  schema: "github.ip_allow_list.v0.PolicyUnsatisfied",
                )
                assert_hydro_messages(count: 1, schema: "github.ip_allow_list.v0.PolicyUnsatisfied")
              end
            end
          end
        end

        context "repository is private" do
          context "when IP allowed" do
            test_actions.each do |action|
              test_with_all_actors "and action is #{description_of action} returns :yes" do
                init_actor_installation @borg_install
                policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @allowed_ip, repository: @brepo, action: action, actor: @actor
                assert_policy_satisfied policy
              end
            end
          end

          context "when IP denied" do
            test_actions.each do |action|
              test_with_actors rando_actor, "and action is #{description_of action} returns :yes" do
                init_actor_installation @borg_install
                policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @denied_ip, repository: @brepo, action: action, actor: @actor
                assert_policy_satisfied policy
              end

              test_with_actors_except no_actor + rando_actor + no_repo_access_actor, "and action is #{description_of action} returns :no" do
                init_actor_installation @borg_install
                policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @denied_ip, repository: @brepo, action: action, actor: @actor
                refute_policy_satisfied policy
              end

              test_with_actors_except no_actor + rando_actor + no_repo_access_actor, "and action is #{description_of action} publishes github.ip_allow_list.v0.PolicyUnsatisfied message to Hydro" do
                init_actor_installation @borg_install
                policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @denied_ip, repository: @brepo, action: action, actor: @actor
                refute_policy_satisfied policy

                expected_payload = {
                  owner_type: :ORG,
                  owner_id: @borg.id,
                  actor_ip: @denied_ip,
                }.update(actor_payload(@actor))
                assert_hydro_published(
                  expected_payload,
                  schema: "github.ip_allow_list.v0.PolicyUnsatisfied",
                )
                assert_hydro_messages(count: 1, schema: "github.ip_allow_list.v0.PolicyUnsatisfied")
              end
            end
          end
        end

        context "when IP allow list enabled on Organization and not on owning Business" do
          context "and IP allowed" do
            test_with_all_actors "returns :yes" do
              init_actor_installation @borg_install
              @bbusiness.disable_ip_allowlist actor: @bbusiness.owners.first
              @borg.enable_ip_allowlist actor: @borg.admin
              policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @allowed_ip, actor: @actor
              assert_policy_satisfied policy
            end

            test_with_integration_actors "returns :no with app access disabled on integration entry" do
              init_actor_installation @borg_install
              @bbusiness.disable_ip_allowlist actor: @bbusiness.owners.first
              @bbusiness.disable_ip_allowlist_app_access actor: @bbusiness.owners.first
              @borg.enable_ip_allowlist actor: @borg.admin
              @borg.disable_ip_allowlist_app_access actor: @borg.admin
              policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @allowed_integration_ip, actor: @actor
              refute_policy_satisfied policy
            end

            test_with_integration_actors "returns :yes with app access disabled on regular entry" do
              init_actor_installation @borg_install
              @bbusiness.disable_ip_allowlist actor: @bbusiness.owners.first
              @bbusiness.disable_ip_allowlist_app_access actor: @bbusiness.owners.first
              @borg.enable_ip_allowlist actor: @borg.admin
              @borg.disable_ip_allowlist_app_access actor: @borg.admin
              policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @allowed_ip, actor: @actor
              assert_policy_satisfied policy
            end

            test_with_integration_actors "returns :yes with user rule enabled" do
              init_actor_installation @borg_install
              @bbusiness.disable_ip_allowlist actor: @bbusiness.owners.first
              @borg.enable_ip_allowlist actor: @borg.admin
              @integration.ip_allowlist_entries.destroy_all
              policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @allowed_ip, actor: @actor
              assert_policy_satisfied policy
            end
          end

          context "and IP denied" do
            test_with_actors rando_actor, "returns :yes" do
              init_actor_installation @borg_install
              @bbusiness.disable_ip_allowlist actor: @bbusiness.owners.first
              @borg.enable_ip_allowlist actor: @borg.admin
              policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @denied_ip, actor: @actor
              assert_policy_satisfied policy
            end

            test_with_actors_except no_actor + rando_actor, "returns :no" do
              init_actor_installation @borg_install
              @bbusiness.disable_ip_allowlist actor: @bbusiness.owners.first
              @borg.enable_ip_allowlist actor: @borg.admin
              policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @denied_ip, actor: @actor
              refute_policy_satisfied policy
            end

            test_with_actors_except no_actor + rando_actor, "does not consider IP allow list entries present on owning Business" do
              init_actor_installation @borg_install

              # Set an allowing entry via `@allowed_ip_range` only on the owning
              # Business which should be ignored, and therefore passing
              # `actor_ip: @allowed_ip` should return false.
              @bbusiness.ip_allowlist_entries.destroy_all
              @borg.ip_allowlist_entries.destroy_all
              @integration.ip_allowlist_entries.destroy_all
              @bbusiness.disable_ip_allowlist actor: @bbusiness.owners.first
              @borg.enable_ip_allowlist actor: @borg.admin
              create :ip_allowlist_entry, owner: @bbusiness, active: true, allow_list_value: @allowed_ip_range

              policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @allowed_ip, actor: @actor
              refute_policy_satisfied policy
            end

            test_with_actors_except no_actor + rando_actor, "publishes github.ip_allow_list.v0.PolicyUnsatisfied message to Hydro" do
              init_actor_installation @borg_install
              @bbusiness.disable_ip_allowlist actor: @bbusiness.owners.first
              @borg.enable_ip_allowlist actor: @borg.admin
              policy = TestIpAllowlistPolicy.new target: @borg, actor_ip: @denied_ip, actor: @actor
              refute_policy_satisfied policy

              expected_payload = {
                owner_type: :ORG,
                owner_id: @borg.id,
                actor_ip: @denied_ip,
              }.update(actor_payload(@actor))
              assert_hydro_published(
                expected_payload,
                schema: "github.ip_allow_list.v0.PolicyUnsatisfied",
              )
              assert_hydro_messages(count: 1, schema: "github.ip_allow_list.v0.PolicyUnsatisfied")
            end
          end
        end
      end

      context "when target is Business" do
        context "when IP allow list enabled" do
          context "with no active entries" do
            test_with_all_actors "returns :yes" do
              init_actor_installation @binstall
              @business.ip_allowlist_entries.destroy_all
              create :ip_allowlist_entry, owner: @business, active: false
              policy = TestIpAllowlistPolicy.new target: @business, actor_ip: @allowed_ip, actor: @actor
              assert_policy_satisfied policy
            end
          end

          context "and IP allowed" do
            test_with_all_actors "returns :yes" do
              init_actor_installation @binstall
              policy = TestIpAllowlistPolicy.new target: @business, actor_ip: @allowed_ip, actor: @actor
              assert_policy_satisfied policy
            end

            test_with_integration_actors "returns :no with app access disabled on integration entry" do
              init_actor_installation @binstall
              @business.disable_ip_allowlist_app_access actor: @business.owners.first
              policy = TestIpAllowlistPolicy.new target: @business, actor_ip: @allowed_integration_ip, actor: @actor
              refute_policy_satisfied policy
            end

            test_with_integration_actors "returns :yes with app access disabled on regular entry" do
              init_actor_installation @binstall
              @business.disable_ip_allowlist_app_access actor: @business.owners.first
              policy = TestIpAllowlistPolicy.new target: @business, actor_ip: @allowed_ip, actor: @actor
              assert_policy_satisfied policy
            end

            test_with_integration_actors "returns :yes with user rule enabled" do
              init_actor_installation @binstall
              @integration.ip_allowlist_entries.destroy_all
              policy = TestIpAllowlistPolicy.new target: @business, actor_ip: @allowed_ip, actor: @actor
              assert_policy_satisfied policy
            end
          end

          context "and IP denied" do
            test_with_actors_except no_actor, "returns :no" do
              init_actor_installation @binstall
              policy = TestIpAllowlistPolicy.new target: @business, actor_ip: @denied_ip, actor: @actor
              refute_policy_satisfied policy
            end

            test_with_actors_except no_actor, "publishes github.ip_allow_list.v0.PolicyUnsatisfied message to Hydro" do
              init_actor_installation @binstall
              policy = TestIpAllowlistPolicy.new target: @business, actor_ip: @denied_ip, actor: @actor
              refute_policy_satisfied policy

              expected_payload = {
                owner_type: :BUSINESS,
                owner_id: @business.id,
                actor_ip: @denied_ip,
              }.update(actor_payload(@actor))
              assert_hydro_published(
                expected_payload,
                schema: "github.ip_allow_list.v0.PolicyUnsatisfied",
              )
              assert_hydro_messages(count: 1, schema: "github.ip_allow_list.v0.PolicyUnsatisfied")
            end
          end
        end
      end

      context "when the app performing on behalf of the actor doesn't take IP allow list into account" do
        context "when IP allow list enabled" do
          test "allows internal app when it is IP exempt" do
            enable_feature_flag(:evaluate_ip_allowlist_satisfied_debug_logging)
            init_actor_installation nil
            @app = create_privileged_app_with_capabilities(capabilities: { ip_allowlist_exempt: true })
            assert Apps::Privileged.capable?(:ip_allowlist_exempt, app: @app), "expected #{@app} to be IP allow list exempt"

            access = @app.grant(@member)
            @member.oauth_access = access

            policy = TestIpAllowlistPolicy.new target: @org, actor_ip: @denied_ip, actor: @member
            expected_keys = { "Body" => "Calculated capable", "gh.is_capable" => "true" }
            assert_logged(**expected_keys) do
              assert_policy_satisfied policy
            end
          end

          test "denies when the app is not IP exempt _and_ the IP doesn't satisfy the policy" do
            init_actor_installation nil
            @app = create(:integration)
            refute Apps::Privileged.capable?(:ip_allowlist_exempt, app: @app), "expected #{@app} to not be IP allow list exempt"

            access = @app.grant(@member)
            @member.oauth_access = access

            policy = TestIpAllowlistPolicy.new target: @org, actor_ip: @denied_ip, actor: @member
            refute_policy_satisfied policy
          end
        end
      end
    else
      test "returns :yes when IP allow lists are not available" do
        init_actor_installation nil
        policy = TestIpAllowlistPolicy.new target: :no_target_for_conditional_access
        assert_policy_satisfied policy
      end
    end
  end
end

module EMUCapIpAllowlistPolicySharedTests
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { EMUCapIpAllowlistPolicyTestBase }

  included do
    T.bind(self, T.class_of(EMUCapIpAllowlistPolicyTestBase))

    context "when target is an EMU (Enterprise Managed User)" do
      context "when IP allow list enabled on owning Business" do
        context "and IP allowed" do
          test_with_all_emu_actors "returns :yes" do
            init_actor_installation @emu_business_install
            policy = TestIpAllowlistPolicy.new target: @emu, actor_ip: @allowed_ip, actor: @actor
            assert_policy_satisfied policy
          end

          test_with_integration_actors "returns :no with app access disabled on integration entry" do
            init_actor_installation @emu_business_install
            @emu_business.disable_ip_allowlist_app_access actor: @owner
            policy = TestIpAllowlistPolicy.new target: @emu, actor_ip: @allowed_integration_ip, actor: @actor
            refute_policy_satisfied policy
          end

          test_with_integration_actors "returns :yes with app access disabled on regular entry" do
            init_actor_installation @emu_business_install
            @emu_business.disable_ip_allowlist_app_access actor: @owner
            policy = TestIpAllowlistPolicy.new target: @emu, actor_ip: @allowed_ip, actor: @actor
            assert_policy_satisfied policy
          end
        end

        context "and IP denied" do
          test_with_emu_actors_except no_actor, "returns :no" do
            init_actor_installation @emu_business_install
            policy = TestIpAllowlistPolicy.new target: @emu, actor_ip: @denied_ip, actor: @actor
            refute_policy_satisfied policy
          end
        end
      end

      context "when IP allow list enabled an Organization" do
        context "and IP allowed" do
          test_with_all_emu_actors "returns :yes" do
            init_actor_installation @emu_org_install
            policy = TestIpAllowlistPolicy.new target: @emu_org, actor_ip: @org_allowed_ip, actor: @actor
            assert_policy_satisfied policy
          end

          test_with_integration_actors "returns :no with app access disabled on integration entry" do
            init_actor_installation @emu_org_install
            @emu_business.disable_ip_allowlist_app_access actor: @owner
            policy = TestIpAllowlistPolicy.new target: @emu_org, actor_ip: @allowed_integration_ip, actor: @actor
            refute_policy_satisfied policy
          end

          test_with_integration_actors "returns :yes with app access disabled on regular entry" do
            init_actor_installation @emu_org_install
            @emu_business.disable_ip_allowlist_app_access actor: @owner
            policy = TestIpAllowlistPolicy.new target: @emu_org, actor_ip: @org_allowed_ip, actor: @actor
            assert_policy_satisfied policy
          end
        end

        context "and IP denied" do
          test_with_emu_actors_except no_actor + rando_actor, "returns :no" do
            init_actor_installation @emu_business_install
            policy = TestIpAllowlistPolicy.new target: @emu_org, actor_ip: @denied_ip, actor: @actor

            refute_policy_satisfied policy
          end
        end
      end

      context "with EMU owned private repository" do
        context "when IP allowed" do
          test_actions.each do |action|
            test_with_all_emu_actors "and action is #{description_of action} returns :yes" do
              init_actor_installation @emu_business_install
              policy = TestIpAllowlistPolicy.new \
                target: @emu, actor_ip: @allowed_ip, repository: @emu_owned_repo, action: action, actor: @actor
              assert_policy_satisfied policy
            end
          end
        end

        context "when IP denied" do
          test_actions.each do |action|
            test_with_emu_actors rando_actor, "and action is #{description_of action} returns :yes" do
              init_actor_installation @emu_business_install
              policy = TestIpAllowlistPolicy.new \
                target: @emu, actor_ip: @denied_ip, repository: @emu_owned_repo, action: action, actor: @actor
              assert_policy_satisfied policy
            end

            test_with_emu_actors_except no_actor + rando_actor + guest_collaborator, "and action is #{description_of action} returns :no" do
              init_actor_installation @emu_business_install
              policy = TestIpAllowlistPolicy.new \
                target: @emu, actor_ip: @denied_ip, repository: @emu_owned_repo, action: action, actor: @actor
              refute_policy_satisfied policy
            end
          end
        end
      end
    end
  end
end

class EMUCapIpAllowlistPolicyTestBase < CapIpAllowlistPolicyBaseTest
  def initialize_fixtures
    @rando = create :user, login: "rando", skip_enterprise_managed_user: true
    @integration = create :integration
    @integration_bot = @integration.bot

    @allowed_ip = "10.10.10.10"
    @allowed_ip_range = "10.10.10.0/24"
    @allowed_integration_ip = "20.20.20.20"
    @allowed_integration_ip_range = "20.20.20.0/24"
    @denied_ip = "1.1.1.1"
    @denied_ip_range = "1.1.1.0/24"

    @org_allowed_ip = "30.30.30.10"
    @org_allowed_ip_range = "30.30.30.0/24"

    @owner = create :emu, :owner
    @emu_business = @owner.enterprise_managed_business
    @emu = create :emu, business: @emu_business
    @non_member_emu = create :emu, business: @emu_business

    @guest_collaborator = create :emu, :guest_collaborator, business: @emu_business

    GitHub::CurrentTenant.set(@emu_business) if GitHub.multi_tenant_enterprise?

    enable_feature_flag(:ip_allowlist_user_level_enforcement, @emu_business)
    @emu_business.enable_ip_allowlist actor: @owner
    @emu_business.enable_ip_allowlist_user_level_enforcement actor: @owner
    @emu_business.enable_ip_allowlist_app_access actor: @owner

    create :ip_allowlist_entry, owner: @emu_business, active: true, allow_list_value: @allowed_ip_range
    @emu_business_install = make_integration_installation(target: @emu_business, integration: @integration, permissions: { Business::Resources.subject_types.first => :read })

    @emu_org = create(:business_plus_org, business: @emu_business, admin: @owner)
    create :ip_allowlist_entry, owner: @emu_org, active: true, allow_list_value: @org_allowed_ip_range

    @emu_org.reload
    @emu_org_install = make_integration_installation target: @emu_org, integration: @integration
    @emu_org.add_member(@emu)

    @emu_owned_repo = create(:private_repository, :minimal, owner: @emu_org)
    @emu_org_repo = create(:repository,  :minimal, owner: @emu_org)

    # Repository Collaborators for EMU
    enable_feature_flag(:repository_collaborators_for_emu, @emu_business)
    assert @emu_owned_repo.can_add_user?(@non_member_emu, @owner)
    @emu_owned_repo.add_member(@non_member_emu, action: :write)
  end

  def initialize_setup
    @actors = [
      nil,
    ]

    @emu_actors = [
      nil,
      @rando,
      @emu,
      @integration_bot,
      @integration,
      @guest_collaborator,
      @non_member_emu,
    ]
  end
end

class EMUCapIpAllowlistPolicyTest < EMUCapIpAllowlistPolicyTestBase
  skip_unless :ip_allowlists_available?

  include EMUCapIpAllowlistPolicySharedTests

  fixtures do
    initialize_fixtures
  end

  setup do
    initialize_setup
  end
end

class MultiTenantCapIpAllowlistPolicyTest < EMUCapIpAllowlistPolicyTestBase
  skip_unless :ip_allowlists_available?

  include EMUCapIpAllowlistPolicySharedTests

  fixtures do
    on_multi_tenant_enterprise
    initialize_fixtures
  end

  setup do
    on_multi_tenant_enterprise
    initialize_setup
  end
end
