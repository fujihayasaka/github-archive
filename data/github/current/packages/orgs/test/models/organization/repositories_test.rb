# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationRepositoriesTest < GitHub::TestCase
  fixtures do
    @admin = create(:user)
    @user = create(:user)
    @enterprise = create(:business, owners: [@admin])
    @enterprise_org = create(:organization, plan: GitHub::Plan.business_plus, admins: [@admin], business: @enterprise)
    @enterprise_org.add_member(@user)
  end

  context "async_can_create_repository?" do
    if GitHub.enterprise?
      test "public repos are able to be created" do
        user = create(:user)
        org = create(:organization)
        org.add_member(user)

        org.async_can_create_repository?(user, visibility: "public").then do |result|
          assert_equal true, result
        end
      end
    end

    test "returns false not nil when org disallows members creating repos" do
      user = create(:user)
      org = create(:organization)
      org.add_member(user)
      org.disallow_members_can_create_repositories(actor: user)

      org.async_can_create_repository?(user).then do |result|
        assert_equal false, result
      end
    end
  end

  context "can_create_repository?" do
    test "can be created by a member of the org's Owners team" do
      owner = create(:user)
      org = create(:organization, admin: owner)

      assert org.can_create_repository?(owner)
    end

    test "can be created by a member of a team with admin permission" do
      member = create(:user)
      org    = create(:organization)
      team   = create(:team, organization: org, permission: "admin")

      refute org.can_create_repository?(member)

      team.add_member(member)
      assert org.can_create_repository?(member)
    end

    test "can't be created by a stranger" do
      org = create(:organization)
      user = create(:user)

      refute org.can_create_repository?(user)
    end

    test "can't be created by logged out user" do
      org = create(:organization)

      refute org.can_create_repository?(nil)
    end

    test "can't be created on an archived organization" do
      admin = create(:user)
      org = create(:archived_organization, admin: admin)

      refute org.can_create_repository?(admin)
    end

    context "granular repo creation permissions" do
      [
        [true, true, true],
        [true, true, false],
        [true, false, true],
        [true, false, false],
        [false, true, true],
        [false, true, false],
        [false, false, true],
        [false, false, false],
      ].each do |public_allowed, private_allowed, internal_allowed|
        test "can_create_repository? returns expected value as member #{public_allowed}-#{private_allowed}-#{internal_allowed}" do
          @enterprise_org.allow_members_can_create_repositories_with_visibilities(actor: @admin,
            public_visibility: public_allowed, private_visibility: private_allowed, internal_visibility: internal_allowed)
          assert_equal private_allowed, @enterprise_org.can_create_repository?(@user, visibility: "private")
          assert_equal public_allowed, @enterprise_org.can_create_repository?(@user, visibility: "public")
          assert_equal internal_allowed, @enterprise_org.can_create_repository?(@user, visibility: "internal")
          assert_equal public_allowed || private_allowed || internal_allowed, @enterprise_org.can_create_repository?(@user)
        end

        test "can_create_repository? returns expected value as admin #{public_allowed}-#{private_allowed}-#{internal_allowed}" do
          @enterprise_org.allow_members_can_create_repositories_with_visibilities(actor: @admin,
            public_visibility: public_allowed, private_visibility: private_allowed, internal_visibility: internal_allowed)
          assert @enterprise_org.can_create_repository?(@admin, visibility: "private")
          assert @enterprise_org.can_create_repository?(@admin, visibility: "public")
          assert @enterprise_org.can_create_repository?(@admin, visibility: "internal")
          assert @enterprise_org.can_create_repository?(@admin)
        end
      end
    end

    context "members_can_create_public_repositories is false" do
      context "as a member" do
        [
          ["private", true],
          ["public", false],
          [:public, false],
          [nil, true],
          [:private, false],
          ["anything", false],
        ].each do |visibility, want|
          test "when visibility is #{visibility.class.name == "String" ? "\"#{visibility}\"" : visibility}" do
            admin_user = create(:user)
            user = create(:user)
            business_org = create(:organization, plan: GitHub::Plan.business_plus, admins: [admin_user])
            business_org.add_member(user)
            business_org.disallow_members_can_create_public_repositories(actor: admin_user)
            assert_equal want, business_org.can_create_repository?(user, visibility: visibility)
          end
        end
      end

      context "as an admin" do
        [
          ["public", true],
          ["private", true],
          ["internal", true],
          [nil, true],
          [false, false],
          ["false", false],
          ["anything", false],
        ].each do |visibility, want|
          test "returns #{want} when visibility is #{visibility.class.name == "String" ? "\"#{visibility}\"" : visibility}" do
            admin_user = create(:user)
            user = create(:user)
            business_org = create(:organization, plan: GitHub::Plan.business_plus, admins: [admin_user])
            business_org.add_member(user)
            business_org.disallow_members_can_create_public_repositories(actor: admin_user)
            assert_equal want, business_org.can_create_repository?(admin_user, visibility: visibility)
          end
        end
      end
    end

    test "can't be created by an org member when members_can_create_repositories is false" do
      org = create(:organization)
      org.disallow_members_can_create_repositories(actor: org.admins.first)

      direct_member = create(:user, login: "direct-member")
      org.add_member(direct_member)

      refute org.can_create_repository?(direct_member)
    end

    test "can be created by an org member who's on a team with a legacy admin permission when members_can_create_repositories is false" do
      org = create(:organization)
      org.disallow_members_can_create_repositories(actor: org.admins.first)

      direct_member = create(:user, login: "direct-member")
      org.add_member(direct_member)

      team = create(:team, organization: org, permission: "admin")
      team.add_member(direct_member)

      assert org.can_create_repository?(direct_member)
    end

    test "can be created by an org member when members_can_create_repositories is true" do
      org = create(:organization)
      org.allow_members_can_create_repositories(actor: org.admins.first)

      direct_member = create(:user, login: "direct-member")
      org.add_member(direct_member)

      assert org.can_create_repository?(direct_member)
    end

    test "can be created by an org owner" do
      org       = create(:organization)
      org_admin = create(:user, login: "org-admin")
      org.add_admin(org_admin)

      assert org.can_create_repository?(org_admin)
    end
  end
end
