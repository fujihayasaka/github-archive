# typed: true
# frozen_string_literal: true

require "test_helper"

class ConditionalAccessTargetProviderTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @repo = create(:repository, :minimal, owner: @org)
    @user = create(:user)
    @business = create(:business)
  end

  setup do
    @target_provider = ConditionalAccess::TargetProvider.new(location: :test, callback_name: "ConditionalAccessTargetProviderTest")
  end

  context "#target values" do
    test "returns a User" do
      obj = Struct.new(:target_for_conditional_access)
      resource = obj.new(@user)
      t = @target_provider.target(resource)
      assert_equal t, @user
    end

    test "returns an Org" do
      obj = Struct.new(:target_for_conditional_access)
      resource = obj.new(@org)
      t = @target_provider.target(resource)
      assert_equal t, @org
    end

    test "returns a Business" do
      obj = Struct.new(:target_for_conditional_access)
      resource = obj.new(@business)
      t = @target_provider.target(resource)
      assert_equal @business, t
    end

    test "doesn't return an unaccepted type" do
      obj = Struct.new(:target_for_conditional_access)
      invalid_target = Object.new
      resource = obj.new(invalid_target)
      assert_raises ArgumentError do
        @target_provider.target(resource)
      end
    end

    test "returns :no_target_for_conditional_access when tfca defined as such" do
      obj = Struct.new(:target_for_conditional_access)
      resource = obj.new(:no_target_for_conditional_access)

      t = @target_provider.target(resource)
      assert_equal :no_target_for_conditional_access, t
    end

    test "returns :no_target_for_conditional_access when given :no_resource_for_conditional_access as a resource" do
      t = @target_provider.target(:no_resource_for_conditional_access)
      assert_equal :no_target_for_conditional_access, t
    end

    test "raises when resource returns nil for target_for_conditional_access and shows id" do
      @repo.stubs(:target_for_conditional_access).returns(nil).once
      ex = assert_raises ArgumentError do
        @target_provider.target(@repo)
      end
      assert_equal "resource Repository#(id: #{@repo.id}) returned nil as target_for_conditional_access", ex.message
    end

    test "raises when resource returns nil for target_for_conditional_access and shows unknown id" do
      res = Object.new
      res.stubs(:target_for_conditional_access).returns(nil).once
      ex = assert_raises ArgumentError do
        @target_provider.target(res)
      end
      assert_equal "resource Object#(id: unknown) returned nil as target_for_conditional_access", ex.message
    end
  end

  context "caching" do
    test "target is cached with resource as a key" do
      obj = Struct.new(:target_for_conditional_access)
      resource = obj.new(@user)
      t = @target_provider.target(resource)
      assert_equal t, @user

      resource_target_cache = @target_provider.instance_variable_get(:@resource_target_cache)
      assert resource_target_cache.has_key?(resource)
      assert_equal resource_target_cache[resource], @user

      # test resource cached is when using the target provider
      @target_provider.expects(:safe_target_for_conditional_access).never
      resource_target_cache.expects(:[]).with(resource).returns(@user)
      t = @target_provider.target(resource)
      assert_equal t, @user
    end

    test "uses safe_target_for_conditional_access to fetch the target and places the target in the cache" do
      obj = Struct.new(:target_for_conditional_access)
      resource = obj.new(@user)
      resource_target_cache = @target_provider.instance_variable_get(:@resource_target_cache)
      # force none cached, then return the cached result
      resource_target_cache.expects(:[]).with(resource).returns(nil).once
      resource_target_cache.expects(:[]=).with(resource, @user).returns(@user).once
      @target_provider.expects(:safe_target_for_conditional_access).with(resource).returns(@user)
      t = @target_provider.target(resource)
      assert_equal t, @user
    end
  end
end
