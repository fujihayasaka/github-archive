# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationSearchTest < GitHub::TestCase
  fixtures do
    setup_search

    @org  = create :organization, login: "organization-search-org"
    @user = create :user, login: "organization-search-user"

    make_searchable @org, @user

    unless GitHub.single_business_environment?
      @soft_deleted_org = create :organization, :soft_deleted, login: "soft-deleted-org", admin: @user
      make_searchable @soft_deleted_org
    end
  end

  teardown_once do
    teardown_search
  end

  if GitHub.single_business_environment?
    test "finds orgs and excludes users" do
      results = Organization.search("organization-search")
      assert_includes results, @org
      refute_includes results, @user
    end
  else
    test "finds active orgs and excludes users and soft-deleted orgs" do
      results = Organization.search("organization-search")
      assert_includes results, @org
      refute_includes results, @user
      refute_includes results, @soft_deleted_org
    end

    test "finds deleted orgs and excludes users and active orgs" do
      results = Organization.search("soft-deleted-org", deleted: true)
      assert_includes results, @soft_deleted_org
      refute_includes results, @user
      refute_includes results, @org
    end
  end
end
