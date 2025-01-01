# typed: true
# frozen_string_literal: true

require "test_helper"

# Represents the controller etc in the different authorization paths, which
# responds to target_for_conditional_access.
class TestIpAllowlistResource
  def initialize(
    target: nil,
    actor_ip: nil,
    repository: nil,
    action: nil,
    actor: nil,
    public_key: nil
  )
    @target = target
    @actor_ip = actor_ip
    @repository = repository
    @action = action
    @actor = actor
    @public_key = public_key
  end

  def target_for_conditional_access
    @target || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
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
end

class ConditionalAccess::TestEnforcer < ConditionalAccess::Enforcer
  include ::ConditionalAccess::Policy::IpAllowlist

  def conditional_access_policies
    [:ip_allowlist]
  end
  alias :registered_policies :conditional_access_policies

  def location
    :test
  end

  def actor
    callback.send(:actor)
  end

  def actor_ip
    callback.send(:actor_ip)
  end

  def repository
    callback.send(:repository)
  end

  def action
    callback.send(:action)
  end
end

class IpAllowlistEnforcerTest < GitHub::TestCase
  fixtures do
    @rando = create :user, login: "rando"
    @member = create :user, login: "member"
    @collaborator = create :user, login: "collaborator"
    @integration = create :integration, default_permissions: { Business::Resources.subject_types.first => :read }
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
      @org.add_member @member
      @repo = create(:private_repository, :minimal, owner: @org)
      @repo.add_member @collaborator
      @public_repo = create(:public_repository, :minimal, owner: @org)
      @public_repo.add_member @collaborator
      @org.enable_ip_allowlist actor: @org.admins.first
      @org.enable_ip_allowlist_app_access actor: @org.admins.first
      create :ip_allowlist_entry, owner: @org, active: true, allow_list_value: @allowed_ip_range
      @org_install = make_integration_installation target: @org, integration: @integration

      @business = create :business
      @business.enable_ip_allowlist actor: @business.owners.first
      @business.enable_ip_allowlist_app_access actor: @business.owners.first
      create :ip_allowlist_entry, owner: @business, active: true, allow_list_value: @allowed_ip_range
      @binstall = make_integration_installation target: @business, integration: @integration

      @borg = create :business_plus_org
      @borg2 = create :business_plus_org
      if GitHub.single_business_environment?
        @bbusiness = GitHub.global_business
        @bbusiness.add_organization(@borg)
        @bbusiness.add_organization(@borg2)
      else
        @bbusiness = create :business, organizations: [@borg, @borg2]
      end
      @borg.add_member @member
      @brepo = create(:private_repository, :minimal, owner: @borg)
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

      @emu = create :emu
      @emu_business = @emu.enterprise_managed_business
      GitHub.flipper[:ip_allowlist_user_level_enforcement].enable(@emu_business)
      @emu_business.enable_ip_allowlist actor: @emu_business.owners.first
      @emu_business.enable_ip_allowlist_user_level_enforcement actor: @emu_business.owners.first
      @emu_business.enable_ip_allowlist_app_access actor: @emu_business.owners.first
      create :ip_allowlist_entry, owner: @emu_business, active: true, allow_list_value: @allowed_ip_range
      @emu_owned_repo = create(:private_repository, :minimal, owner: @emu)
      @emu_business_install = make_integration_installation target: @emu_business, integration: @integration
    end
  end

  setup do
    @actors = [
      nil,
      @rando,
      @member,
      @collaborator,
      @integration_bot,
      @integration,
    ]
    @emu_actors = [
      nil,
      @rando,
      @emu,
      @integration_bot,
      @integration,
    ]
  end

  def init_actor_installation(installation)
    @actor.installation = installation if @actor.respond_to?(:installation=)
  end

  def assert_result(resource, result)
    enforcer = ConditionalAccess::TestEnforcer.new resource
    results = enforcer.evaluate_conditional_access_policies resource
    assert_equal 1, results.size
    assert_equal :ip_allowlist, results.keys.first
    assert_equal result, results.values.first
  end

  def assert_satisfied(resource)
    assert_result(resource, :satisfied)
  end

  def assert_unsatisfied(resource)
    assert_result(resource, :unsatisfied)
  end

  def assert_inapplicable(resource)
    assert_result(resource, :inapplicable)
  end

  def self.no_actor
    [0]
  end

  def self.rando_actor
    [1]
  end

  def self.integration_installation_actor
    [4]
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
      block: T.proc.bind(IpAllowlistEnforcerTest).void
    ).void
  end
  def self.test_with_actors(actors, name, &block)
    test_actor_context_names = [
      "without actor",
      "with actor",
      "with member actor",
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
      block: T.proc.bind(IpAllowlistEnforcerTest).void
    ).void
  end
  def self.test_with_all_user_actors(name, &block)
    test_with_actors([0, 1, 2, 3], name, &block)
  end

  sig do
    params(
      actors: T::Array[Integer],
      name: String,
      block: T.proc.bind(IpAllowlistEnforcerTest).void
    ).void
  end
  def self.test_with_user_actors_except(actors, name, &block)
    test_with_actors([0, 1, 2, 3] - actors, name, &block)
  end

  sig do
    params(
      name: String,
      block: T.proc.bind(IpAllowlistEnforcerTest).void
    ).void
  end
  def self.test_with_integration_actors(name, &block)
    test_with_actors([4, 5], name, &block)
  end

  sig do
    params(
      name: String,
      block: T.proc.bind(IpAllowlistEnforcerTest).void
    ).void
  end
  def self.test_with_all_actors(name, &block)
    test_with_actors([0, 1, 2, 3, 4, 5], name, &block)
  end

  sig do
    params(
      actors: T::Array[Integer],
      name: String,
      block: T.proc.bind(IpAllowlistEnforcerTest).void
    ).void
  end
  def self.test_with_actors_except(actors, name, &block)
    test_with_actors([0, 1, 2, 3, 4, 5] - actors, name, &block)
  end

  sig do
    params(
      actors: T::Array[Integer],
      name: String,
      block: T.proc.bind(IpAllowlistEnforcerTest).void
    ).void
  end
  def self.test_with_emu_actors(actors, name, &block)
    test_actor_context_names = [
      "without actor",
      "with actor",
      "with member actor",
      "with installed integration",
      "with integration",
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
      block: T.proc.bind(IpAllowlistEnforcerTest).void
    ).void
  end
  def self.test_with_all_emu_user_actors(name, &block)
    test_with_emu_actors([0, 1, 2], name, &block)
  end

  sig do
    params(
      actors: T::Array[Integer],
      name: String,
      block: T.proc.bind(IpAllowlistEnforcerTest).void
    ).void
  end
  def self.test_with_emu_user_actors_except(actors, name, &block)
    test_with_emu_actors([0, 1, 2] - actors, name, &block)
  end

  sig do
    params(
      name: String,
      block: T.proc.bind(IpAllowlistEnforcerTest).void
    ).void
  end
  def self.test_with_emu_integration_actors(name, &block)
    test_with_emu_actors([3, 4], name, &block)
  end

  sig do
    params(
      name: String,
      block: T.proc.bind(IpAllowlistEnforcerTest).void
    ).void
  end
  def self.test_with_all_emu_actors(name, &block)
    test_with_emu_actors([0, 1, 2, 3, 4], name, &block)
  end

  sig do
    params(
      actors: T::Array[Integer],
      name: String,
      block: T.proc.bind(IpAllowlistEnforcerTest).void
    ).void
  end
  def self.test_with_emu_actors_except(actors, name, &block)
    test_with_emu_actors([0, 1, 2, 3, 4] - actors, name, &block)
  end

  context "#evaluate_conditional_access_policies" do
    if GitHub.ip_allowlists_available?
      test "returns :inapplicable when target is nil" do
        init_actor_installation nil
        resource = TestIpAllowlistResource.new target: nil
        assert_inapplicable resource
      end

      test "returns :inapplicable when target is a regular User" do
        init_actor_installation nil
        resource = TestIpAllowlistResource.new target: create(:user)
        assert_inapplicable resource
      end

      context "when target is Organization" do
        context "when IP allow list is disabled" do
          test_with_all_actors "returns :inapplicable" do
            init_actor_installation @org_install
            @org.disable_ip_allowlist actor: @org.admins.first
            resource = TestIpAllowlistResource.new target: @org, actor: @actor
            assert_inapplicable resource
          end
        end

        context "when IP allow list is enabled" do
          context "with no active entries" do
            test_with_actors no_actor, "returns :inapplicable" do
              init_actor_installation @org_install
              @org.ip_allowlist_entries.destroy_all
              create :ip_allowlist_entry, owner: @org, active: false
              resource = TestIpAllowlistResource.new target: @org, actor: @actor
              assert_inapplicable resource
            end

            test_with_user_actors_except no_actor, "returns :satisfied" do
              init_actor_installation @org_install
              @org.ip_allowlist_entries.destroy_all
              create :ip_allowlist_entry, owner: @org, active: false
              resource = TestIpAllowlistResource.new target: @org, actor: @actor
              assert_satisfied resource
            end

            test_with_integration_actors "returns :unsatisfied" do
              init_actor_installation @org_install
              @org.ip_allowlist_entries.destroy_all
              create :ip_allowlist_entry, owner: @org, active: false
              resource = TestIpAllowlistResource.new target: @org, actor: @actor
              assert_unsatisfied resource
            end
          end

          context "and IP allowed" do
            test_with_actors no_actor, "returns :inapplicable" do
              init_actor_installation @org_install
              resource = TestIpAllowlistResource.new target: @org, actor_ip: @allowed_ip, actor: @actor
              assert_inapplicable resource
            end

            test_with_actors_except no_actor, "returns :satisfied" do
              init_actor_installation @org_install
              resource = TestIpAllowlistResource.new target: @org, actor_ip: @allowed_ip, actor: @actor
              assert_satisfied resource
            end

            test_with_integration_actors "returns :unsatisfied with app access disabled on integration entry" do
              init_actor_installation @org_install
              @org.disable_ip_allowlist_app_access actor: @org.admin
              resource = TestIpAllowlistResource.new target: @org, actor_ip: @allowed_integration_ip, actor: @actor
              assert_unsatisfied resource
            end

            test_with_integration_actors "returns :satisfied with app access disabled on regular entry" do
              init_actor_installation @org_install
              @org.disable_ip_allowlist_app_access actor: @org.admin
              resource = TestIpAllowlistResource.new target: @org, actor_ip: @allowed_ip, actor: @actor
              assert_satisfied resource
            end

            test_with_integration_actors "returns :satisfied with user rule enabled" do
              init_actor_installation @org_install
              @integration.ip_allowlist_entries.destroy_all
              resource = TestIpAllowlistResource.new target: @org, actor_ip: @allowed_ip, actor: @actor
              assert_satisfied resource
            end
          end

          context "and IP denied" do
            test_with_actors no_actor, "returns :inapplicable" do
              init_actor_installation @org_install
              resource = TestIpAllowlistResource.new target: @org, actor_ip: @denied_ip, actor: @actor
              assert_inapplicable resource
            end

            test_with_actors rando_actor, "returns :satisfied" do
              init_actor_installation @org_install
              resource = TestIpAllowlistResource.new target: @org, actor_ip: @denied_ip, actor: @actor
              assert_satisfied resource
            end

            test_with_actors_except no_actor + rando_actor, "returns :unsatisfied" do
              init_actor_installation @org_install
              resource = TestIpAllowlistResource.new target: @org, actor_ip: @denied_ip, actor: @actor
              assert_unsatisfied resource
            end
          end

          context "and IP matches custom hosted runner" do
            test_with_actors_except no_actor + rando_actor, "returns :unsatisfied in dotcom" do
              GitHub.actions_runner_ip_ranges = [@denied_ip_range]
              init_actor_installation @org_install
              resource = TestIpAllowlistResource.new target: @org, actor_ip: @denied_ip, actor: @actor
              assert_unsatisfied resource
            end
          end
        end

        context "repository is public" do
          context "when IP allowed" do
            test_actions.each do |action|
              test_with_actors no_actor, "and action is #{action} returns :inapplicable" do
                init_actor_installation @org_install
                resource = TestIpAllowlistResource.new target: @org, actor_ip: @allowed_ip, repository: @public_repo, action: action, actor: @actor
                assert_inapplicable resource
              end

              test_with_actors_except no_actor, "and action is #{action} returns :satisfied" do
                init_actor_installation @org_install
                resource = TestIpAllowlistResource.new target: @org, actor_ip: @allowed_ip, repository: @public_repo, action: action, actor: @actor
                assert_satisfied resource
              end
            end
          end

          context "when IP denied" do
            context "but action is nil" do
              test_with_actors no_actor, "returns :inapplicable" do
                init_actor_installation @org_install
                resource = TestIpAllowlistResource.new target: @org, actor_ip: @denied_ip, repository: @public_repo, action: nil, actor: @actor
                assert_inapplicable resource
              end

              test_with_actors rando_actor, "returns :satisfied" do
                init_actor_installation @org_install
                resource = TestIpAllowlistResource.new target: @org, actor_ip: @denied_ip, repository: @public_repo, action: nil, actor: @actor
                assert_satisfied resource
              end

              test_with_actors_except no_actor + rando_actor, "returns :unsatisfied" do
                init_actor_installation @org_install
                resource = TestIpAllowlistResource.new target: @org, actor_ip: @denied_ip, repository: @public_repo, action: nil, actor: @actor
                assert_unsatisfied resource
              end
            end

            context "and action is :read" do
              test_with_actors no_actor, "returns :inapplicable" do
                init_actor_installation @org_install
                resource = TestIpAllowlistResource.new target: @org, actor_ip: @denied_ip, repository: @public_repo, action: :read, actor: @actor
                assert_inapplicable resource
              end

              test_with_actors_except no_actor, "returns :satisfied" do
                init_actor_installation @org_install
                resource = TestIpAllowlistResource.new target: @org, actor_ip: @denied_ip, repository: @public_repo, action: :read, actor: @actor
                assert_satisfied resource
              end
            end

            context "and action is :write" do
              test_with_actors no_actor, "returns :inapplicable" do
                init_actor_installation @org_install
                resource = TestIpAllowlistResource.new target: @org, actor_ip: @denied_ip, repository: @public_repo, action: :write, actor: @actor
                assert_inapplicable resource
              end

              test_with_actors rando_actor, "returns :satisfied" do
                init_actor_installation @org_install
                resource = TestIpAllowlistResource.new target: @org, actor_ip: @denied_ip, repository: @public_repo, action: :write, actor: @actor
                assert_satisfied resource
              end

              test_with_actors_except no_actor + rando_actor, "returns :unsatisfied" do
                init_actor_installation @org_install
                resource = TestIpAllowlistResource.new target: @org, actor_ip: @denied_ip, repository: @public_repo, action: :write, actor: @actor
                assert_unsatisfied resource
              end
            end
          end
        end

        context "repository is private" do
          context "when IP allowed" do
            test_actions.each do |action|
              test_with_actors no_actor, "and action is #{description_of action} returns :inapplicable" do
                init_actor_installation @org_install
                resource = TestIpAllowlistResource.new target: @org, actor_ip: @allowed_ip, repository: @repo, action: action, actor: @actor
                assert_inapplicable resource
              end

              test_with_actors_except no_actor, "and action is #{description_of action} returns :satisfied" do
                init_actor_installation @org_install
                resource = TestIpAllowlistResource.new target: @org, actor_ip: @allowed_ip, repository: @repo, action: action, actor: @actor
                assert_satisfied resource
              end
            end
          end

          context "when IP denied" do
            test_actions.each do |action|
              test_with_actors no_actor, "and action is #{description_of action} returns :inapplicable" do
                init_actor_installation @org_install
                resource = TestIpAllowlistResource.new target: @org, actor_ip: @denied_ip, repository: @repo, action: action, actor: @actor
                assert_inapplicable resource
              end

              test_with_actors rando_actor, "and action is #{description_of action} returns :satisfied" do
                init_actor_installation @org_install
                resource = TestIpAllowlistResource.new target: @org, actor_ip: @denied_ip, repository: @repo, action: action, actor: @actor
                assert_satisfied resource
              end

              test_with_actors_except no_actor + rando_actor, "and action is #{description_of action} returns :unsatisfied" do
                init_actor_installation @org_install
                resource = TestIpAllowlistResource.new target: @org, actor_ip: @denied_ip, repository: @repo, action: action, actor: @actor
                assert_unsatisfied resource
              end
            end
          end
        end
      end

      context "when target is business-owned Organization" do
        context "when IP allow list disabled" do
          test_with_all_actors "returns :inapplicable" do
            init_actor_installation @borg_install
            @bbusiness.disable_ip_allowlist actor: @bbusiness.owners.first
            resource = TestIpAllowlistResource.new target: @borg, actor: @actor
            assert_inapplicable resource
          end
        end

        context "when IP allow list enabled on owning Business" do
          context "and IP allowed" do
            test_with_actors no_actor, "returns :inapplicable" do
              init_actor_installation @borg_install
              resource = TestIpAllowlistResource.new target: @borg, actor_ip: @allowed_ip, actor: @actor
              assert_inapplicable resource
            end

            test_with_actors_except no_actor, "returns :satisfied" do
              init_actor_installation @borg_install
              resource = TestIpAllowlistResource.new target: @borg, actor_ip: @allowed_ip, actor: @actor
              assert_satisfied resource
            end

            test_with_integration_actors "returns :unsatisfied with app access disabled on integration entry" do
              init_actor_installation @borg_install
              @bbusiness.disable_ip_allowlist_app_access actor: @bbusiness.owners.first
              resource = TestIpAllowlistResource.new target: @borg, actor_ip: @allowed_integration_ip, actor: @actor
              assert_unsatisfied resource
            end

            test_with_integration_actors "returns :satisfied with app access disabled on regular entry" do
              init_actor_installation @borg_install
              @bbusiness.disable_ip_allowlist_app_access actor: @bbusiness.owners.first
              resource = TestIpAllowlistResource.new target: @borg, actor_ip: @allowed_ip, actor: @actor
              assert_satisfied resource
            end

            test_with_integration_actors "returns :satisfied with user rule enabled" do
              init_actor_installation @borg_install
              @integration.ip_allowlist_entries.destroy_all
              resource = TestIpAllowlistResource.new target: @borg, actor_ip: @allowed_ip, actor: @actor
              assert_satisfied resource
            end
          end

          context "and IP allowed at the org level but not at the business level" do
            test "returns :satisfied when owner is org" do
              init_actor_installation @borg_install
              org_admin = create :user
              org = create :business_plus_org, admin: org_admin
              org.disable_ip_allowlist actor: org_admin
              @business.add_organization org
              create :ip_allowlist_entry, owner: org, active: true, allow_list_value: "8.8.8.8/8"
              org.reload

              resource = TestIpAllowlistResource.new target: org, actor_ip: "8.8.8.8", actor: org_admin
              assert_satisfied resource
            end

            test "returns :unsatisfied when owner is business" do
              init_actor_installation @borg_install
              org_admin = create :user
              org = create :business_plus_org, admin: org_admin
              @business.add_organization org
              create :ip_allowlist_entry, owner: org, active: true, allow_list_value: "8.8.8.8/8"
              org.reload

              resource = TestIpAllowlistResource.new target: @business, actor_ip: "8.8.8.8", actor: org_admin
              assert_unsatisfied resource
            end
          end

          context "and IP denied" do
            test_with_actors no_actor, "returns :inapplicable" do
              init_actor_installation @borg_install
              resource = TestIpAllowlistResource.new target: @borg, actor_ip: @denied_ip, actor: @actor
              assert_inapplicable resource
            end

            test_with_actors rando_actor, "returns :satisfied" do
              init_actor_installation @borg_install
              resource = TestIpAllowlistResource.new target: @borg, actor_ip: @denied_ip, actor: @actor
              assert_satisfied resource
            end

            test_with_actors_except no_actor + rando_actor, "returns :unsatisfied" do
              init_actor_installation @borg_install
              resource = TestIpAllowlistResource.new target: @borg, actor_ip: @denied_ip, actor: @actor
              assert_unsatisfied resource
            end

            test "with member in other enterprise owned org returns :unsatisfied" do
              # @borg and @borg2 are owned by @bbusiness, @borg2_member is only a member of @borg2
              init_actor_installation @borg_install
              resource = TestIpAllowlistResource.new target: @borg, actor_ip: @denied_ip, actor: @borg2_member
              assert_unsatisfied resource
            end
          end
        end

        context "repository is public" do
          context "when IP allowed" do
            test_actions.each do |action|
              test_with_actors no_actor, "and action is #{action} returns :inapplicable" do
                init_actor_installation @borg_install
                resource = TestIpAllowlistResource.new target: @borg, actor_ip: @allowed_ip, repository: @bpublic_repo, action: action, actor: @actor
                assert_inapplicable resource
              end

              test_with_actors_except no_actor, "and action is #{action} returns :satisfied" do
                init_actor_installation @borg_install
                resource = TestIpAllowlistResource.new target: @borg, actor_ip: @allowed_ip, repository: @bpublic_repo, action: action, actor: @actor
                assert_satisfied resource
              end
            end
          end

          context "when IP denied" do
            context "but action is nil" do
              test_with_actors no_actor, "returns :inapplicable" do
                init_actor_installation @borg_install
                resource = TestIpAllowlistResource.new target: @borg, actor_ip: @denied_ip, repository: @bpublic_repo, action: nil, actor: @actor
                assert_inapplicable resource
              end

              test_with_actors rando_actor, "returns :satisfied" do
                init_actor_installation @borg_install
                resource = TestIpAllowlistResource.new target: @borg, actor_ip: @denied_ip, repository: @bpublic_repo, action: nil, actor: @actor
                assert_satisfied resource
              end

              test_with_actors_except no_actor + rando_actor, "returns :unsatisfied" do
                init_actor_installation @borg_install
                resource = TestIpAllowlistResource.new target: @borg, actor_ip: @denied_ip, repository: @bpublic_repo, action: nil, actor: @actor
                assert_unsatisfied resource
              end
            end

            context "and action is :read" do
              test_with_actors no_actor, "returns :inapplicable" do
                init_actor_installation @borg_install
                resource = TestIpAllowlistResource.new target: @borg, actor_ip: @denied_ip, repository: @bpublic_repo, action: :read, actor: @actor
                assert_inapplicable resource
              end

              test_with_actors_except no_actor, "returns :satisfied" do
                init_actor_installation @borg_install
                resource = TestIpAllowlistResource.new target: @borg, actor_ip: @denied_ip, repository: @bpublic_repo, action: :read, actor: @actor
                assert_satisfied resource
              end
            end

            context "and action is :write" do
              test_with_actors no_actor, "returns :inapplicable" do
                init_actor_installation @borg_install
                resource = TestIpAllowlistResource.new target: @borg, actor_ip: @denied_ip, repository: @bpublic_repo, action: :write, actor: @actor
                assert_inapplicable resource
              end

              test_with_actors rando_actor, "returns :satisfied" do
                init_actor_installation @borg_install
                resource = TestIpAllowlistResource.new target: @borg, actor_ip: @denied_ip, repository: @bpublic_repo, action: :write, actor: @actor
                assert_satisfied resource
              end

              test_with_actors_except no_actor + rando_actor, "returns :unsatisfied" do
                init_actor_installation @borg_install
                resource = TestIpAllowlistResource.new target: @borg, actor_ip: @denied_ip, repository: @bpublic_repo, action: :write, actor: @actor
                assert_unsatisfied resource
              end
            end
          end
        end

        context "repository is internal" do
          context "when IP allowed" do
            test_actions.each do |action|
              test_with_actors no_actor, "and action is #{description_of action} returns :inapplicable" do
                init_actor_installation @borg2_install
                resource = TestIpAllowlistResource.new target: @borg2, actor_ip: @allowed_ip, repository: @internal_repo, action: action, actor: @actor
                assert_inapplicable resource
              end

              test_with_actors_except no_actor, "and action is #{description_of action} returns :satisfied" do
                init_actor_installation @borg2_install
                resource = TestIpAllowlistResource.new target: @borg2, actor_ip: @allowed_ip, repository: @internal_repo, action: action, actor: @actor
                assert_satisfied resource
              end
            end
          end

          context "when IP denied" do
            test_actions.each do |action|
              test_with_actors no_actor, "and action is #{description_of action} returns :inapplicable" do
                init_actor_installation @borg2_install
                resource = TestIpAllowlistResource.new target: @borg2, actor_ip: @denied_ip, repository: @internal_repo, action: action, actor: @actor
                assert_inapplicable resource
              end

              test_with_actors_except no_actor, "and action is #{description_of action} returns :unsatisfied" do
                init_actor_installation @borg2_install
                resource = TestIpAllowlistResource.new target: @borg2, actor_ip: @denied_ip, repository: @internal_repo, action: action, actor: @actor
                assert_unsatisfied resource
              end
            end
          end
        end

        context "repository is private" do
          context "when IP allowed" do
            test_actions.each do |action|
              test_with_actors no_actor, "and action is #{description_of action} returns :inapplicable" do
                init_actor_installation @borg_install
                resource = TestIpAllowlistResource.new target: @borg, actor_ip: @allowed_ip, repository: @brepo, action: action, actor: @actor
                assert_inapplicable resource
              end

              test_with_actors_except no_actor, "and action is #{description_of action} returns :satisfied" do
                init_actor_installation @borg_install
                resource = TestIpAllowlistResource.new target: @borg, actor_ip: @allowed_ip, repository: @brepo, action: action, actor: @actor
                assert_satisfied resource
              end
            end
          end

          context "when IP denied" do
            test_actions.each do |action|
              test_with_actors no_actor, "and action is #{description_of action} returns :inapplicable" do
                init_actor_installation @borg_install
                resource = TestIpAllowlistResource.new target: @borg, actor_ip: @denied_ip, repository: @brepo, action: action, actor: @actor
                assert_inapplicable resource
              end

              test_with_actors rando_actor, "and action is #{description_of action} returns :satisfied" do
                init_actor_installation @borg_install
                resource = TestIpAllowlistResource.new target: @borg, actor_ip: @denied_ip, repository: @brepo, action: action, actor: @actor
                assert_satisfied resource
              end

              test_with_actors_except no_actor + rando_actor, "and action is #{description_of action} returns :unsatisfied" do
                init_actor_installation @borg_install
                resource = TestIpAllowlistResource.new target: @borg, actor_ip: @denied_ip, repository: @brepo, action: action, actor: @actor
                assert_unsatisfied resource
              end
            end
          end
        end

        context "when IP allow list enabled on Organization and not on owning Business" do
          context "and IP allowed" do
            test_with_actors no_actor, "returns :inapplicable" do
              init_actor_installation @borg_install
              @bbusiness.disable_ip_allowlist actor: @bbusiness.owners.first
              @borg.enable_ip_allowlist actor: @borg.admin
              resource = TestIpAllowlistResource.new target: @borg, actor_ip: @allowed_ip, actor: @actor
              assert_inapplicable resource
            end

            test_with_actors_except no_actor, "returns :satisfied" do
              init_actor_installation @borg_install
              @bbusiness.disable_ip_allowlist actor: @bbusiness.owners.first
              @borg.enable_ip_allowlist actor: @borg.admin
              resource = TestIpAllowlistResource.new target: @borg, actor_ip: @allowed_ip, actor: @actor
              assert_satisfied resource
            end

            test_with_integration_actors "returns :unsatisfied with app access disabled on integration entry" do
              init_actor_installation @borg_install
              @bbusiness.disable_ip_allowlist actor: @bbusiness.owners.first
              @bbusiness.disable_ip_allowlist_app_access actor: @bbusiness.owners.first
              @borg.enable_ip_allowlist actor: @borg.admin
              @borg.disable_ip_allowlist_app_access actor: @borg.admin
              resource = TestIpAllowlistResource.new target: @borg, actor_ip: @allowed_integration_ip, actor: @actor
              assert_unsatisfied resource
            end

            test_with_integration_actors "returns :satisfied with app access disabled on regular entry" do
              init_actor_installation @borg_install
              @bbusiness.disable_ip_allowlist actor: @bbusiness.owners.first
              @bbusiness.disable_ip_allowlist_app_access actor: @bbusiness.owners.first
              @borg.enable_ip_allowlist actor: @borg.admin
              @borg.disable_ip_allowlist_app_access actor: @borg.admin
              resource = TestIpAllowlistResource.new target: @borg, actor_ip: @allowed_ip, actor: @actor
              assert_satisfied resource
            end

            test_with_integration_actors "returns :satisfied with user rule enabled" do
              init_actor_installation @borg_install
              @bbusiness.disable_ip_allowlist actor: @bbusiness.owners.first
              @borg.enable_ip_allowlist actor: @borg.admin
              @integration.ip_allowlist_entries.destroy_all
              resource = TestIpAllowlistResource.new target: @borg, actor_ip: @allowed_ip, actor: @actor
              assert_satisfied resource
            end
          end

          context "and IP denied" do
            test_with_actors no_actor, "returns :inapplicable" do
              init_actor_installation @borg_install
              @bbusiness.disable_ip_allowlist actor: @bbusiness.owners.first
              @borg.enable_ip_allowlist actor: @borg.admin
              resource = TestIpAllowlistResource.new target: @borg, actor_ip: @denied_ip, actor: @actor
              assert_inapplicable resource
            end

            test_with_actors rando_actor, "returns :satisfied" do
              init_actor_installation @borg_install
              @bbusiness.disable_ip_allowlist actor: @bbusiness.owners.first
              @borg.enable_ip_allowlist actor: @borg.admin
              resource = TestIpAllowlistResource.new target: @borg, actor_ip: @denied_ip, actor: @actor
              assert_satisfied resource
            end

            test_with_actors_except no_actor + rando_actor, "returns :unsatisfied" do
              init_actor_installation @borg_install
              @bbusiness.disable_ip_allowlist actor: @bbusiness.owners.first
              @borg.enable_ip_allowlist actor: @borg.admin
              resource = TestIpAllowlistResource.new target: @borg, actor_ip: @denied_ip, actor: @actor
              assert_unsatisfied resource
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

              resource = TestIpAllowlistResource.new target: @borg, actor_ip: @allowed_ip, actor: @actor
              assert_unsatisfied resource
            end
          end
        end
      end

      context "when target is Business" do
        context "when IP allow list disabled" do
          test_with_all_actors "returns :inapplicable" do
            init_actor_installation @binstall
            @business.disable_ip_allowlist actor: @business.owners.first
            resource = TestIpAllowlistResource.new target: @business, actor: @actor
            assert_inapplicable resource
          end
        end

        context "when IP allow list enabled" do
          context "with no active entries" do
            test_with_actors no_actor, "returns :inapplicable" do
              init_actor_installation @binstall
              @business.ip_allowlist_entries.destroy_all
              create :ip_allowlist_entry, owner: @business, active: false
              resource = TestIpAllowlistResource.new target: @business, actor_ip: @allowed_ip, actor: @actor
              assert_inapplicable resource
            end

            test_with_actors_except no_actor, "returns :satisfied" do
              init_actor_installation @binstall
              @business.ip_allowlist_entries.destroy_all
              create :ip_allowlist_entry, owner: @business, active: false
              resource = TestIpAllowlistResource.new target: @business, actor_ip: @allowed_ip, actor: @actor
              assert_satisfied resource
            end
          end

          context "and IP allowed" do
            test_with_actors no_actor, "returns :inapplicable" do
              init_actor_installation @binstall
              resource = TestIpAllowlistResource.new target: @business, actor_ip: @allowed_ip, actor: @actor
              assert_inapplicable resource
            end

            test_with_actors_except no_actor, "returns :satisfied" do
              init_actor_installation @binstall
              resource = TestIpAllowlistResource.new target: @business, actor_ip: @allowed_ip, actor: @actor
              assert_satisfied resource
            end

            test_with_integration_actors "returns :unsatisfied with app access disabled on integration entry" do
              init_actor_installation @binstall
              @business.disable_ip_allowlist_app_access actor: @business.owners.first
              resource = TestIpAllowlistResource.new target: @business, actor_ip: @allowed_integration_ip, actor: @actor
              assert_unsatisfied resource
            end

            test_with_integration_actors "returns :satisfied with app access disabled on regular entry" do
              init_actor_installation @binstall
              @business.disable_ip_allowlist_app_access actor: @business.owners.first
              resource = TestIpAllowlistResource.new target: @business, actor_ip: @allowed_ip, actor: @actor
              assert_satisfied resource
            end

            test_with_integration_actors "returns :satisfied with user rule enabled" do
              init_actor_installation @binstall
              @integration.ip_allowlist_entries.destroy_all
              resource = TestIpAllowlistResource.new target: @business, actor_ip: @allowed_ip, actor: @actor
              assert_satisfied resource
            end
          end

          context "and IP denied" do
            test_with_actors_except no_actor, "returns :unsatisfied" do
              init_actor_installation @binstall
              resource = TestIpAllowlistResource.new target: @business, actor_ip: @denied_ip, actor: @actor
              assert_unsatisfied resource
            end

            test_with_actors no_actor, "returns :inapplicable" do
              init_actor_installation @binstall
              resource = TestIpAllowlistResource.new target: @business, actor_ip: @denied_ip, actor: @actor
              assert_inapplicable resource
            end
          end
        end
      end

      context "when target is an EMU (Enterprise Managed User)" do
        context "when IP allow list disabled" do
          test_with_all_emu_actors "returns :inapplicable" do
            init_actor_installation @emu_business_install
            @emu_business.disable_ip_allowlist actor: @emu_business.owners.first
            resource = TestIpAllowlistResource.new target: @emu, actor: @actor
            assert_inapplicable resource
          end
        end

        context "when IP allow list is enabled" do
          context "with no active entries" do
            test_with_emu_actors no_actor, "returns :inapplicable" do
              init_actor_installation @emu_business_install
              @emu_business.ip_allowlist_entries.destroy_all
              create :ip_allowlist_entry, owner: @emu_business, active: false
              resource = TestIpAllowlistResource.new target: @emu, actor: @actor
              assert_inapplicable resource
            end

            test_with_emu_user_actors_except no_actor, "returns :satisfied" do
              init_actor_installation @emu_business_install
              @emu_business.ip_allowlist_entries.destroy_all
              create :ip_allowlist_entry, owner: @emu_business, active: false
              resource = TestIpAllowlistResource.new target: @emu, actor: @actor
              assert_satisfied resource
            end

            test_with_emu_integration_actors "returns :unsatisfied" do
              init_actor_installation @emu_business_install
              @emu_business.ip_allowlist_entries.destroy_all
              create :ip_allowlist_entry, owner: @emu_business, active: false
              resource = TestIpAllowlistResource.new target: @emu, actor: @actor
              assert_unsatisfied resource
            end
          end

          context "and IP allowed" do
            test_with_emu_actors no_actor, "returns :inapplicable" do
              init_actor_installation @emu_business_install
              resource = TestIpAllowlistResource.new target: @emu, actor_ip: @allowed_ip, actor: @actor
              assert_inapplicable resource
            end

            test_with_emu_actors_except no_actor, "returns :satisfied" do
              init_actor_installation @emu_business_install
              resource = TestIpAllowlistResource.new target: @emu, actor_ip: @allowed_ip, actor: @actor
              assert_satisfied resource
            end

            test_with_emu_integration_actors "returns :unsatisfied with app access disabled on integration entry" do
              init_actor_installation @emu_business_install
              @emu_business.disable_ip_allowlist_app_access actor: @emu_business.owners.first
              resource = TestIpAllowlistResource.new target: @emu, actor_ip: @allowed_integration_ip, actor: @actor
              assert_unsatisfied resource
            end

            test_with_emu_integration_actors "returns :satisfied with app access disabled on regular entry" do
              init_actor_installation @emu_business_install
              @emu_business.disable_ip_allowlist_app_access actor: @emu_business.owners.first
              resource = TestIpAllowlistResource.new target: @emu, actor_ip: @allowed_ip, actor: @actor
              assert_satisfied resource
            end

            test_with_emu_integration_actors "returns :satisfied with user rule enabled" do
              init_actor_installation @emu_business_install
              @integration.ip_allowlist_entries.destroy_all
              resource = TestIpAllowlistResource.new target: @emu, actor_ip: @allowed_ip, actor: @actor
              assert_satisfied resource
            end
          end

          context "and IP denied" do
            test_with_emu_actors no_actor, "returns :inapplicable" do
              init_actor_installation @emu_business_install
              resource = TestIpAllowlistResource.new target: @emu, actor_ip: @denied_ip, actor: @actor
              assert_inapplicable resource
            end

            test_with_emu_actors_except no_actor + rando_actor, "returns :unsatisfied" do
              init_actor_installation @emu_business_install
              resource = TestIpAllowlistResource.new target: @emu, actor_ip: @denied_ip, actor: @actor
              assert_unsatisfied resource
            end
          end

          context "with EMU-owned repository" do
            context "when IP allowed" do
              test_actions.each do |action|
                test_with_emu_actors no_actor, "and action is #{description_of action} returns :inapplicable" do
                  init_actor_installation @emu_business_install
                  resource = TestIpAllowlistResource.new \
                    target: @emu, actor_ip: @allowed_ip, repository: @emu_owned_repo, action: action, actor: @actor
                  assert_inapplicable resource
                end

                test_with_emu_actors_except no_actor, "and action is #{description_of action} returns :satisfied" do
                  init_actor_installation @emu_business_install
                  resource = TestIpAllowlistResource.new \
                    target: @emu, actor_ip: @allowed_ip, repository: @emu_owned_repo, action: action, actor: @actor
                  assert_satisfied resource
                end
              end
            end

            context "when IP denied" do
              test_actions.each do |action|
                test_with_emu_actors no_actor, "and action is #{description_of action} returns :inapplicable" do
                  init_actor_installation @emu_business_install
                  resource = TestIpAllowlistResource.new \
                    target: @emu, actor_ip: @denied_ip, repository: @emu_owned_repo, action: action, actor: @actor
                  assert_inapplicable resource
                end

                test_with_emu_actors rando_actor, "and action is #{description_of action} returns :satisfied" do
                  init_actor_installation @emu_business_install
                  resource = TestIpAllowlistResource.new \
                    target: @emu, actor_ip: @denied_ip, repository: @emu_owned_repo, action: action, actor: @actor
                  assert_satisfied resource
                end

                test_with_emu_actors_except no_actor + rando_actor, "and action is #{description_of action} returns :unsatisfied" do
                  init_actor_installation @emu_business_install
                  resource = TestIpAllowlistResource.new \
                    target: @emu, actor_ip: @denied_ip, repository: @emu_owned_repo, action: action, actor: @actor
                  assert_unsatisfied resource
                end
              end
            end
          end

        end
      end

      context "when the app performing on behalf of the actor doesn't take IP allow list into account" do
        context "when IP allow list enabled" do
          test "allows internal app when it is IP exempt" do
            init_actor_installation nil
            @app = create_privileged_app_with_capabilities(capabilities: { ip_allowlist_exempt: true })
            assert Apps::Privileged.capable?(:ip_allowlist_exempt, app: @app), "expected #{@app} to be IP allow list exempt"

            access = @app.grant(@member)
            @member.oauth_access = access

            resource = TestIpAllowlistResource.new target: @org, actor_ip: @denied_ip, actor: @member
            assert_satisfied resource
          end

          test "denies when the app is not IP exempt _and_ the IP doesn't satisfy the policy" do
            init_actor_installation nil
            @app = create(:integration)
            refute Apps::Privileged.capable?(:ip_allowlist_exempt, app: @app), "expected #{@app} to not be IP allow list exempt"

            access = @app.grant(@member)
            @member.oauth_access = access

            resource = TestIpAllowlistResource.new target: @org, actor_ip: @denied_ip, actor: @member
            assert_unsatisfied resource
          end
        end
      end
    else
      test "returns :inapplicable when IP allow lists are not available" do
        init_actor_installation nil
        resource = TestIpAllowlistResource.new(target: nil)
        assert_inapplicable resource
      end
    end
  end
end
