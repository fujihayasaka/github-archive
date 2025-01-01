# typed: true
# frozen_string_literal: true

require "test_helper"

class CasMappingTest < GitHub::TestCase
  fixtures do
    @mapping = create :cas_mapping
    @user = create(:user)
  end

  context "validations" do
    test "ensure an associated user" do
      mapping = CasMapping.new user: nil, username: "wiley"

      refute_predicate mapping, :valid?
      assert_includes mapping.errors[:user], "can't be blank"
    end

    test "ensure an username is present" do
      mapping = CasMapping.new user: @user, username: ""

      refute_predicate mapping, :valid?
      assert_includes mapping.errors[:username], "can't be blank"
    end

    test "ensure that username is not already taken" do
      mapping = CasMapping.new user: @user, username: @mapping.username
      refute_predicate mapping, :valid?
      assert_includes mapping.errors[:username], "has already been taken"

      mapping = CasMapping.new user: @user, username: @mapping.username.upcase
      refute mapping.valid?
      assert_includes mapping.errors[:username], "has already been taken"
    end
  end

  test "raises a uniqueness error if multiple mappings are created for a single user" do
    assert_raises ActiveRecord::RecordNotUnique do
      create :cas_mapping, user: @mapping.user, username: "take2"
    end
  end
end
