# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationSearchTest < GitHub::TestCase
  fixtures do
    setup_search

    @org  = create :organization, login: "organization-search-org"
    @user = create :user, login: "organization-search-user"
    @soft_deleted_org = create :organization, :soft_deleted, login: "soft-deleted-org", admin: @user

    make_searchable @org, @soft_deleted_org, @user
  end

  teardown_once do
    teardown_search
  end

  test "finds orgs and excludes users and soft-deleted orgs" do
    results = Organization.search("organization-search")
    assert_includes results, @org
    refute_includes results, @user
    refute_includes results, @soft_deleted_org
  end
end
