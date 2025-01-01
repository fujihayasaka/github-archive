# typed: true
# frozen_string_literal: true

require "test_helper"

class PrereleaseProgramMemberTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create(:organization)
    @business = create(:business)
  end

  context "validation" do
    test "requires member" do
      beta_program_member = PrereleaseProgramMember.new(member: nil)
      refute beta_program_member.valid?
      refute_empty beta_program_member.errors[:member]
    end

    test "requires actor" do
      beta_program_member = PrereleaseProgramMember.new(actor: nil)
      refute beta_program_member.valid?
      refute_empty beta_program_member.errors[:actor]
    end

    test "requires actor to be a user" do
      beta_program_member = PrereleaseProgramMember.new(actor: @org)
      refute beta_program_member.valid?
      refute_empty beta_program_member.errors[:actor]
    end

    test "member can be a User" do
      beta_program_member = PrereleaseProgramMember.new \
        member: @user, actor: @user
      assert beta_program_member.valid?
      assert_empty beta_program_member.errors[:member]
    end

    test "member can be an Organization" do
      beta_program_member = PrereleaseProgramMember.new \
        member: @org, actor: @org.admins.first
      assert beta_program_member.valid?
      assert_empty beta_program_member.errors[:member]
    end

    test "member can be a Business" do
      beta_program_member = PrereleaseProgramMember.new \
        member: @business, actor: @business.owners.first
      assert beta_program_member.valid?
      assert_empty beta_program_member.errors[:member]
    end
  end

  context "::member?" do
    test "false when a user is not in the program" do
      refute PrereleaseProgramMember.member?(@user)
    end

    test "false when an org is not in the program" do
      refute PrereleaseProgramMember.member?(@org)
    end

    test "false when a business is not in the program" do
      refute PrereleaseProgramMember.member?(@business)
    end

    test "true when a user is in the program" do
      PrereleaseProgramMember.create \
        member: @user, actor: @user
      assert PrereleaseProgramMember.member?(@user)
    end

    test "true when an org is in the program" do
      PrereleaseProgramMember.create \
        member: @org, actor: @org.admins.first
      assert PrereleaseProgramMember.member?(@org)
    end

    test "true when a business is in the program" do
      PrereleaseProgramMember.create \
        member: @business, actor: @business.owners.first
      assert PrereleaseProgramMember.member?(@business)
    end
  end
end
