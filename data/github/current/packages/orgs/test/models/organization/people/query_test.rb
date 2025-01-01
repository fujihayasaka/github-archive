# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationPeopleQueryTest < GitHub::TestCase
  fixtures do
    @org = create(:organization, login: "the-org")
    @admin = @org.admin
    @member = create(:user, login: "member")
    @member.emails.each(&:verify!)
    @stranger = create(:user)
  end

  setup do
    @org.add_member(@member)
  end

  context "#cleaned_query" do
    test "it does not extract non-sensical roles, but it sanitizes and strips" do
      weird_role_query = "role:this_does_not_make_sense "
      result = Organization::People::Query.new(
        query: weird_role_query,
        organization: @org,
        current_user: @admin,
        role: nil,
      ).cleaned_query

      assert_equal ActiveRecord::Base.sanitize_sql_like(weird_role_query).strip,
        result
    end

    test "sets role instance variable to direct member if it matches member" do
      result = Organization::People::Query.new(
        query: "role:member ",
        organization: @org,
        current_user: @admin,
        role: nil,
      )

      # welp, it's a side effect
      result.cleaned_query

      assert_equal :direct_member, result.role
    end

    test "sets role instance variable to owner if it matches" do
      result = Organization::People::Query.new(
        query: "role:owner ",
        organization: @org,
        current_user: @admin,
        role: nil,
      )

      # welp, it's a side effect
      result.cleaned_query

      assert_equal :owner, result.role
    end

    test "strips ROLE_QUERY if role query present" do
      result = Organization::People::Query.new(
        query: "role:owner ",
        organization: @org,
        current_user: @admin,
        role: nil,
      ).cleaned_query

      assert_equal "", result
    end

    test "strips EXTERNAL_IDENTITY_LINKED_QUERY" do
      T.bind(self, OrganizationPeopleQueryTest)
      result = Organization::People::Query.new(
        query: "#{Organization::People::Query::EXTERNAL_IDENTITY_LINKED_QUERY} ",
        organization: @org,
        current_user: @admin,
        role: nil,
      ).cleaned_query

      assert_equal "", result
    end

    test "strips EXTERNAL_IDENTITY_UNLINKED_QUERY" do
      result = Organization::People::Query.new(
        query: "#{Organization::People::Query::EXTERNAL_IDENTITY_UNLINKED_QUERY} ",
        organization: @org,
        current_user: @admin,
        role: nil,
      ).cleaned_query

      assert_equal "", result
    end

    test "strips TWO_FACTOR_ENABLED_QUERY" do
      result = Organization::People::Query.new(
        query: "#{Organization::People::Query::TWO_FACTOR_ENABLED_QUERY} ",
        organization: @org,
        current_user: @admin,
        role: nil,
      ).cleaned_query

      assert_equal "", result
    end

    test "strips TWO_FACTOR_DISABLED_QUERY" do
      result = Organization::People::Query.new(
        query: "#{Organization::People::Query::TWO_FACTOR_DISABLED_QUERY} ",
        organization: @org,
        current_user: @admin,
        role: nil,
      ).cleaned_query

      assert_equal "", result
    end

    test "strips TWO_FACTOR_REQUIRED_QUERY" do
      result = Organization::People::Query.new(
        query: "#{Organization::People::Query::TWO_FACTOR_REQUIRED_QUERY} ",
        organization: @org,
        current_user: @admin,
        role: nil,
      ).cleaned_query

      assert_equal "", result
    end

    test "strips ORGANIZATION_MEMBERSHIP_GROUP_QUERY" do
      result = Organization::People::Query.new(
        query: "#{Organization::People::Query::ORGANIZATION_MEMBERSHIP_GROUP_QUERY} ",
        organization: @org,
        current_user: @admin,
        role: nil,
      ).cleaned_query

      assert_equal "", result
    end

    test "strips ORGANIZATION_MEMBERSHIP_ADMIN_QUERY" do
      result = Organization::People::Query.new(
        query: "#{Organization::People::Query::ORGANIZATION_MEMBERSHIP_ADMIN_QUERY} ",
        organization: @org,
        current_user: @admin,
        role: nil,
      ).cleaned_query

      assert_equal "", result
    end

    test "strips INVITATION_SOURCE if source query present" do
      result = Organization::People::Query.new(
        query: "source:member ",
        organization: @org,
        current_user: @admin,
        role: nil,
      ).cleaned_query

      assert_equal "", result
    end

    test "strips SORT if sort query present" do
      result = Organization::People::Query.new(
        query: "sort:created_asc ",
        organization: @org,
        current_user: @admin,
        role: nil,
      ).cleaned_query

      assert_equal "", result
    end
  end

  context "#searching?" do
    test "when cleaned_query is present it returns true" do
      result = Organization::People::Query.new(
        query: "some search query",
        organization: @org,
        current_user: @admin,
        role: nil,
      )

      assert_predicate result, :searching?
    end

    test "when cleaned_query is not present it returns false" do
      result = Organization::People::Query.new(
        query: "",
        organization: @org,
        current_user: @admin,
        role: nil,
      )

      refute_predicate result, :searching?
    end
  end

  context "role_match" do
    test "when ROLE_QUERY matches owner, it returns :owner" do
      result = Organization::People::Query.new(
        query: "role:owner",
        organization: @org,
        current_user: @admin,
        role: nil,
      ).role_match

      assert_equal :owner, result
    end

    test "when ROLE_QUERY matches member, it returns :member" do
      result = Organization::People::Query.new(
        query: "role:member",
        organization: @org,
        current_user: @admin,
        role: nil,
      ).role_match

      assert_equal :member, result
    end

    test "when ROLE_QUERY matches guest_collaborator, it returns :guest_collaborator" do
      result = Organization::People::Query.new(
        query: "role:guest_collaborator",
        organization: @org,
        current_user: @admin,
        role: nil,
      ).role_match

      assert_equal :guest_collaborator, result
    end
  end

  context "invitation_source_match" do
    test "when INVITATION_SOURCE_QUERY matches member, it returns :member" do
      result = Organization::People::Query.new(
        query: "source:member",
        organization: @org,
        current_user: @admin,
        role: nil,
      ).invitation_source_match

      assert_equal :member, result
    end

    test "when INVITATION_SOURCE_QUERY matches scim, it returns :scim" do
      result = Organization::People::Query.new(
        query: "source:scim",
        organization: @org,
        current_user: @admin,
        role: nil,
      ).invitation_source_match

      assert_equal :scim, result
    end
  end

  context "sort_match" do
    test "when SORT_QUERY matches title-desc, it returns :title and :asc" do
      result = Organization::People::Query.new(
        query: "sort:title_asc",
        organization: @org,
        current_user: @admin,
        role: nil,
      )

      assert_equal :title, result.sort_field_match
      assert_equal :asc, result.sort_direction_match
    end

    test "when SORT_QUERY matches created-desc, it returns :created-at and :desc" do
      result = Organization::People::Query.new(
        query: "sort:created_desc",
        organization: @org,
        current_user: @admin,
        role: nil,
      )

      assert_equal :created, result.sort_field_match
      assert_equal :desc, result.sort_direction_match
    end
  end

  context "#two_factor_disabled_scope?" do
    test "when query does contain the correct phrase it returns true" do
      result = Organization::People::Query.new(
        query: Organization::People::Query::TWO_FACTOR_DISABLED_QUERY,
        organization: @org,
        current_user: @admin,
        role: nil,
      )

      assert_predicate result, :two_factor_disabled_scope?
    end

    test "when query does not contain the correct phrase it returns false" do
      result = Organization::People::Query.new(
        query: "",
        organization: @org,
        current_user: @admin,
        role: nil,
      )

      refute_predicate result, :two_factor_disabled_scope?
    end

    test "when org is not adminable by current user it returns false" do
      result = Organization::People::Query.new(
        query: Organization::People::Query::TWO_FACTOR_DISABLED_QUERY,
        organization: @org,
        current_user: @member,
        role: nil,
      )

      refute_predicate result, :two_factor_disabled_scope?
    end
  end

  context "#two_factor_enabled_scope?" do
    test "when query does contain the correct phrase it returns true" do
      result = Organization::People::Query.new(
        query: Organization::People::Query::TWO_FACTOR_ENABLED_QUERY,
        organization: @org,
        current_user: @admin,
        role: nil,
      )

      assert_predicate result, :two_factor_enabled_scope?
    end

    test "when query does not contain the correct phrase it returns false" do
      result = Organization::People::Query.new(
        query: "",
        organization: @org,
        current_user: @admin,
        role: nil,
      )

      refute_predicate result, :two_factor_enabled_scope?
    end

    test "when org is not adminable by current user it returns false" do
      result = Organization::People::Query.new(
        query: Organization::People::Query::TWO_FACTOR_ENABLED_QUERY,
        organization: @org,
        current_user: @member,
        role: nil,
      )

      refute_predicate result, :two_factor_enabled_scope?
    end
  end

  context "#two_factor_required_scope?" do
    test "when query does contain the correct phrase it returns true" do
      result = Organization::People::Query.new(
        query: Organization::People::Query::TWO_FACTOR_REQUIRED_QUERY,
        organization: @org,
        current_user: @admin,
        role: nil,
      )

      assert_predicate result, :two_factor_required_scope?
    end

    test "when query does not contain the correct phrase it returns false" do
      result = Organization::People::Query.new(
        query: "",
        organization: @org,
        current_user: @admin,
        role: nil,
      )

      refute_predicate result, :two_factor_required_scope?
    end

    test "when org is not adminable by current user it returns false" do
      result = Organization::People::Query.new(
        query: Organization::People::Query::TWO_FACTOR_REQUIRED_QUERY,
        organization: @org,
        current_user: @member,
        role: nil,
      )

      refute_predicate result, :two_factor_required_scope?
    end
  end

  context "#organization_membership_group_scope?" do
    test "when query does contain the correct phrase it returns true" do
      result = Organization::People::Query.new(
        query: Organization::People::Query::ORGANIZATION_MEMBERSHIP_GROUP_QUERY,
        organization: @org,
        current_user: @admin,
        role: nil,
      )

      assert_predicate result, :organization_membership_group_scope?
    end

    test "when query does not contain the correct phrase it returns false" do
      result = Organization::People::Query.new(
        query: "",
        organization: @org,
        current_user: @admin,
        role: nil,
      )

      refute_predicate result, :organization_membership_group_scope?
    end

    test "when org is not adminable by current user it returns false" do
      result = Organization::People::Query.new(
        query: Organization::People::Query::ORGANIZATION_MEMBERSHIP_GROUP_QUERY,
        organization: @org,
        current_user: @member,
        role: nil,
      )

      refute_predicate result, :organization_membership_group_scope?
    end
  end

  context "#organization_membership_admin_scope?" do
    test "when query does contain the correct phrase it returns true" do
      result = Organization::People::Query.new(
        query: Organization::People::Query::ORGANIZATION_MEMBERSHIP_ADMIN_QUERY,
        organization: @org,
        current_user: @admin,
        role: nil,
      )

      assert_predicate result, :organization_membership_admin_scope?
    end

    test "when query does not contain the correct phrase it returns false" do
      result = Organization::People::Query.new(
        query: "",
        organization: @org,
        current_user: @admin,
        role: nil,
      )

      refute_predicate result, :organization_membership_admin_scope?
    end

    test "when org is not adminable by current user it returns false" do
      result = Organization::People::Query.new(
        query: Organization::People::Query::ORGANIZATION_MEMBERSHIP_ADMIN_QUERY,
        organization: @org,
        current_user: @member,
        role: nil,
      )

      refute_predicate result, :organization_membership_admin_scope?
    end
  end

  context "#external_identity_linked_scope?" do
    test "when query does contain the correct phrase it returns true" do
      result = Organization::People::Query.new(
        query: Organization::People::Query::EXTERNAL_IDENTITY_LINKED_QUERY,
        organization: @org,
        current_user: @admin,
        role: nil,
      )

      assert_predicate result, :external_identity_linked_scope?
    end

    test "when query does not contain the correct phrase it returns false" do
      result = Organization::People::Query.new(
        query: "",
        organization: @org,
        current_user: @admin,
        role: nil,
      )

      refute_predicate result, :external_identity_linked_scope?
    end

    test "when org is not adminable by current user it returns false" do
      result = Organization::People::Query.new(
        query: Organization::People::Query::EXTERNAL_IDENTITY_LINKED_QUERY,
        organization: @org,
        current_user: @member,
        role: nil,
      )

      refute_predicate result, :external_identity_linked_scope?
    end
  end

  context "#external_identity_unlinked_scope?" do
    test "when query does contain the correct phrase it returns true" do
      result = Organization::People::Query.new(
        query: Organization::People::Query::EXTERNAL_IDENTITY_UNLINKED_QUERY,
        organization: @org,
        current_user: @admin,
        role: nil,
      )

      assert_predicate result, :external_identity_unlinked_scope?
    end

    test "when query does not contain the correct phrase it returns false" do
      result = Organization::People::Query.new(
        query: "",
        organization: @org,
        current_user: @admin,
        role: nil,
      )

      refute_predicate result, :external_identity_unlinked_scope?
    end

    test "when org is not adminable by current user it returns false" do
      result = Organization::People::Query.new(
        query: Organization::People::Query::EXTERNAL_IDENTITY_UNLINKED_QUERY,
        organization: @org,
        current_user: @member,
        role: nil,
      )

      refute_predicate result, :external_identity_unlinked_scope?
    end
  end

  context "#role_scope?" do
    test "when role_match is truthy and the user is an org member it returns true" do
      result = Organization::People::Query.new(
        query: "role:member",
        organization: @org,
        current_user: @member,
        role: nil,
      )

      assert_predicate result, :role_scope?
    end

    test "when role_match is falsey and the user is an org member it returns false" do
      result = Organization::People::Query.new(
        query: "",
        organization: @org,
        current_user: @member,
        role: nil,
      )

      refute_predicate result, :role_scope?
    end

    test "when role_match is truthy and the user is not an org member it returns false" do
      result = Organization::People::Query.new(
        query: "role:member",
        organization: @org,
        current_user: @stranger,
        role: nil,
      )

      refute_predicate result, :role_scope?
    end
  end
end
