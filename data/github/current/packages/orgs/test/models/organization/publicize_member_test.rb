# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationPublicizeMemberTest < GitHub::TestCase
  fixtures do
    @org  = create(:organization)
    @user = create(:user, login: "to-be-publicized")
  end

  test "cannot publicize a nil user" do
    refute @org.publicize_member(nil)
  end

  test "cannot publicize an unaffiliated user" do
    @org.publicize_member(@user)
    refute @org.public_member?(@user)
  end

  test "can publicize a team member" do
    create(:team, organization: @org).add_member(@user)
    @org.publicize_member(@user)

    assert @org.public_member?(@user)
  end

  test "can publicize an org member" do
    @org.add_member(@user)
    @org.publicize_member(@user)

    assert @org.public_member?(@user)
  end

  test "can publicize an org owner" do
    @org.add_admin(@user)
    @org.publicize_member(@user)

    assert @org.public_member?(@user)
  end
end
