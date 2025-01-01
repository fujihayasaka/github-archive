# typed: true
# frozen_string_literal: true

require "test_helper"
class EnterpriseNavigation::Links::SharedDependencyTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers
  include GitHub::Memoizer

  fixtures do
    @user = create(:user)
    @business = create(:business, owners: [@user])
    @permission = :test_permission
  end

  class ExampleComponent < ApplicationComponent
    include EnterpriseNavigation::Links::SharedDependency

    sig { returns T.nilable(Business) }
    attr_reader :business

    sig { returns T.nilable(User) }
    attr_reader :user

    sig do
      params(
        user: T.nilable(User),
        business: T.nilable(Business),
      ).void
    end
    def initialize(user: nil, business: nil)
      @user = user
      @business = business
    end
  end

  setup do
    @extended = ExampleComponent.new(user: @user, business: @business)
  end

  test "Has access to business" do
    assert_equal @business, @extended.business
  end

  test "Has access to user" do
    assert_equal @user, @extended.user
  end

  context "#user_has_business_permission?" do
    test "returns false when business is nil" do
      Authz.domain.expects(:check_allowed).never
      no_business = ExampleComponent.new(user: @user, business: nil)

      refute no_business.user_has_business_permission?(@permission)
    end

    test "returns false when user is nil" do
      Authz.domain.expects(:check_allowed).never
      no_user = ExampleComponent.new(user: nil, business: @business)

      refute no_user.user_has_business_permission?(@permission)
    end

    test "returns false when permission is nil" do
      Authz.domain.expects(:check_allowed).never

      refute @extended.user_has_business_permission?(nil)
    end

    test "returns false when user does not have correct permission" do
      Authz.domain.expects(:check_allowed).with(@user, @permission, @business).returns(false)

      refute @extended.user_has_business_permission?(@permission)
    end

    test "returns true when user has correct permission" do
      Authz.domain.expects(:check_allowed).with(@user, @permission, @business).returns(true)

      assert @extended.user_has_business_permission?(@permission)
    end
  end
end
