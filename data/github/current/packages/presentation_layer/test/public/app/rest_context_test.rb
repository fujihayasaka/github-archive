# typed: true
# frozen_string_literal: true

require "test_helper"

class RestContextTest < GitHub::TestCase
  FIND_REPO_METHOD = :find_active
  class FakeController
    include App::IController

    def initialize(user)
      @env = {}
      @params = {}
      @current_user = user
    end
    attr_reader :env, :params, :current_user
  end

  setup do
    @controller = FakeController.new(stub_interface(Users::IUser, {}))
    @context = App::RestContext.new(app: @controller)
  end

  context "#repository" do
    test "fetches the corresponding repository once" do
      repo = stub_interface(Repositories::IRepository, {})
      Repositories::Domain.any_instance.expects(:active_by_id).once.with(9000).returns(repo)
      @controller.params[:repository_id] = "9000.lols"

      assert_equal repo, @context.repository
      assert_equal repo, @context.repository
    end

    test "returns whatever is in 'this repository' in the env if there is something" do
      repo = stub_interface(Repositories::IRepository, {})
      @controller.env[GitHub::Routers::Api::ThisRepositoryKey] = repo

      # assert same object hash so we know it is the same instance
      assert_equal repo.object_id, @context.repository.object_id
    end

    test "only tries to load the repository once when it can't be found" do
      Repositories::Domain.any_instance.expects(:active_by_id).once.with(9000).returns(nil)
      @controller.params[:repository_id] = "9000.lols"

      assert_nil @context.repository
      assert_nil @context.repository
    end

    test "caches not found when id is useless" do
      # This isn't the greatest assertion, but I'm not sure how to assert that we didn't query the domain
      Repositories::Public.expects(FIND_REPO_METHOD).never
      @controller.params[:repository_id] = "invalid"

      assert_nil @context.repository

      # This is also sinful but it's important to know we are caching the not found result
      cached_value = @context.instance_variable_get(:@repository)
      assert_equal GH::Result::Error::NotFound, cached_value.class
    end

    test "doesn't cache anything when id is unspecified" do
      repo = stub_interface(Repositories::IRepository, {})
      Repositories::Domain.any_instance.expects(:active_by_id).once.with(10).returns(repo)
      assert_nil @context.repository

      @controller.params[:repository_id] = "10"
      assert_equal repo, @context.repository
    end
  end

  context "#actor" do
    test "returns the current user and caches it" do
      user = stub_interface(Users::IUser, {})
      controller = FakeController.new(user)

      controller.expects(:current_user).once.returns(user)

      @context = App::RestContext.new(app: controller)

      assert_equal user.object_id, @context.actor.object_id
      assert_equal user.object_id, @context.actor.object_id
    end

    test "returns nil and caches it if there is no current user" do
      controller = FakeController.new(nil)

      controller.expects(:current_user).once.returns(nil)

      @context = App::RestContext.new(app: controller)

      assert_nil @context.actor
      assert_nil @context.actor
    end
  end

  context "#organization" do
    test "fetches the corresponding organization once" do
      org = stub_interface(Orgs::IOrganization, {})
      Orgs::OrganizationAccessor.any_instance.expects(:by_id).once.with(9000).returns(org)
      @controller.params[:organization_id] = "9000"

      assert_equal org, @context.organization
      assert_equal org, @context.organization
    end

    test "returns the org in 'this user' from the env if it is an org" do
      org = stub_interface(Orgs::IOrganization, { active?: true })
      @controller.env[GitHub::Routers::Api::ThisUserKey] = org

      # assert same object hash so we know it is the same instance
      assert_equal org.object_id, @context.organization.object_id
    end

    test "only tries to load the org once when it can't be found" do
      Orgs::OrganizationAccessor.any_instance.expects(:by_id).once.with(9000).returns(nil)
      @controller.params[:organization_id] = "9000.lols"

      assert_nil @context.organization
      assert_nil @context.organization
    end

    test "loads the organization by name after failing id lookup" do
      org = stub_interface(Orgs::IOrganization, {})
      Orgs::OrganizationAccessor.any_instance.expects(:by_name).once.with("fraggle").returns(org)
      @controller.params[:org] = "fraggle"

      assert_equal org, @context.organization
      assert_equal org, @context.organization
    end

    test "caches not found when id and name are useless" do
      # This isn't the greatest assertion, but I'm not sure how to assert that we didn't query the domain
      Orgs::OrganizationAccessor.any_instance.expects(:by_id).once.with(0).returns(nil)
      @controller.params[:organization_id] = "invalid"

      assert_nil @context.organization

      # This is also sinful but it's important to know we are caching the not found result
      cached_value = @context.instance_variable_get(:@organization)
      assert_equal GH::Result::Error::NotFound, cached_value.class
    end
  end

  context "#find_business" do
    test "fetches the corresponding business if an enterprise_id is provided" do
      enterprise_id = 1
      Business.expects(:find_by).with(id: enterprise_id).returns(nil)
      Business.expects(:find_by).with(slug: enterprise_id).returns(nil)

      @controller.params[:enterprise_id] = enterprise_id

      assert_nil @context.business
    end

    test "does not attempt to fetches the corresponding business if no enterprise_id is provided" do
      Business.expects(:find_by).with(any_parameters).never

      assert_nil @context.business
    end
  end

  context "#user" do
    test "fetches the corresponding user once" do
      user = stub_interface(Users::IUser, {})
      Users::Domain.any_instance.expects(:by_id).once.with(9000).returns(user)
      @controller.params[:user_id] = "9000"

      assert_equal user, @context.user
      assert_equal user, @context.user
    end

    test "returns the user in 'this user' from the env" do
      user = stub_interface(Users::IUser, {})
      @controller.env[GitHub::Routers::Api::ThisUserKey] = user

      # assert same object hash so we know it is the same instance
      assert_equal user.object_id, @context.user.object_id
    end

    test "only tries to load the user once when it can't be found" do
      Users::Domain.any_instance.expects(:by_id).once.with(9000).returns(nil)
      @controller.params[:user_id] = "9000.lols"

      assert_nil @context.user
      assert_nil @context.user
    end

    test "caches not found when id is useless" do
      # This isn't the greatest assertion, but I'm not sure how to assert that we didn't query the domain
      Users::Domain.any_instance.expects(:by_id).once.with(0).returns(nil)
      @controller.params[:user_id] = "invalid"

      assert_nil @context.user

      # This is also sinful but it's important to know we are caching the not found result
      cached_value = @context.instance_variable_get(:@user)
      assert_equal GH::Result::Error::NotFound, cached_value.class
    end
  end

  context "#resource_org_or_biz_owner" do
    test "returns the org if it is already set, even if biz is as well" do
      org = stub_interface(Orgs::IOrganization, {})
      business = stub_interface(Admin::IBusiness, {})
      @context.organization = org
      @context.business = business
      assert_equal org, @context.resource_org_or_biz_owner
    end

    test "returns the biz if the org is unspecified" do
      business = stub_interface(Admin::IBusiness, {})
      @context.business = business
      assert_equal business, @context.resource_org_or_biz_owner
    end

    test "doesn't even touch the controller if both are missing" do
      controller = FakeController.new(nil)
      controller.expects(:params).never
      controller.expects(:env).never

      @context = App::RestContext.new(app: controller)
      @context.resource_org_or_biz_owner
    end
  end

  private

  # Public: create a stub object that implements the given abstract module, with return values as
  # specified in the given hash.
  def stub_interface(abstract_module, stub_hash)
    klass = Class.new do
      include abstract_module

      stub_hash.each do |method, value|
        define_method(method) { value }
      end
    end
    klass.new
  end
end
