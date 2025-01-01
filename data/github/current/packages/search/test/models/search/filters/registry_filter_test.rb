# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFiltersRegistryFilterTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @user_with_nothing = create(:user)
    @user_with_only_private_repo = create(:user)
    @public_repo = create(:repository, owner: @user)
    @private_repo = create(:private_repository, owner: @user)
    @private_repo_3 = create(:private_repository, owner: @user_with_only_private_repo)

    @org = create(:organization, admin: @user)

    @other_org = create(:organization, admin: @user_with_nothing)
    @private_org_repo = create(:private_repository, owner: @other_org)
  end

  setup do
    @qualifiers = Search::ParsedQuery.qualifiers
  end

  teardown_once do
  end

  # Deleted only logic changes the must conditions for a filter. Since most of the versin specific changes happen in the shoulds, this
  # flag needs to be tested independently to ensure that the proper filters are being provided.
  context "deleted_only logic" do
    test "if only_deleted_packages, the correct musts are included" do
      filter = Search::Filters::RegistryFilter.new(current_user: @user, only_deleted_packages: true, qualifiers: @qualifiers)

      expected_must = [
        { exists: { field: "deleted_at" } },
        {
          range: {
            deleted_at: {
              gte: "now-30d",
              lt: "now"
            }
          }
        }
      ]

      expected_must_not = []

      assert_equal(expected_must, filter.must)
      assert_equal(expected_must_not, filter.must_not)
    end

    test "if only_deleted_packages, the correct must_nots are included" do
      filter = Search::Filters::RegistryFilter.new(current_user: @user, qualifiers: @qualifiers)

      expected_must = [
        { exists: { field: "versions" } }
      ]

      expected_must_not = [
        {
          exists: {
            field: "deleted_at"
          }
        }
      ]

      assert_equal(expected_must, filter.must)
      assert_equal(expected_must_not, filter.must_not)
    end
  end

  # Note that package type is added in the query
  # TODO: move package_type into filter
  context "package_type" do
    test "package_type not provided" do
      filter = Search::Filters::RegistryFilter.new(current_user: @user, qualifiers: @qualifiers)

      expected_must = [
        { exists: { field: "versions" } }
      ]

      expected_must_not = [
        {
          exists: {
            field: "deleted_at"
          }
        }
      ]

      assert_equal(expected_must, filter.must)
      assert_equal(expected_must_not, filter.must_not)
    end
  end

  context "anonymous search" do
    test "only includes public packages" do
      filter = Search::Filters::RegistryFilter.new(current_user: nil, qualifiers: @qualifiers)

      expected_should = [
        { term: { public: true } }
      ]

      assert_equal(expected_should, filter.should)
    end
  end

  context "logged in search" do
    test "where current user has private repositories" do
      filter = Search::Filters::RegistryFilter.new(current_user: @user, qualifiers: @qualifiers)
      filter.stubs(:package_ids).returns([])

      expected_must = [
        { exists: { field: "versions" } }
      ]

      expected_should = [
        { term: { public: true } },
        { term: { repo_id: @private_repo.id } },
        { terms: { _id: [] } },
        {
          bool: {
            must: [
              { term: { author_type: 0 } },
              { term: { author_id: @user.id } }
            ]
          }
        },
        { term: { namespace: @user.login } },
        { terms: { namespace: [@org.login] } },
        {
          bool: {
            must: [
              { match: { visibility: { query: "internal" } } },
              { terms: { namespace: [@org.login] } }
            ]
          }
        }
      ]

      expected_must_not = [
        {
          exists: {
            field: "deleted_at"
          }
        }
      ]

      assert_equal(expected_must, filter.must)
      assert_equal(expected_must_not, filter.must_not)
      assert_equal(expected_should, filter.should)
    end
  end

  context "with owner specified" do
    test "where owner has no repos" do
      filter = Search::Filters::RegistryFilter.new(current_user: @user_with_nothing, owner_id: @user_with_nothing.id, qualifiers: @qualifiers)
      filter.stubs(:package_ids).returns([])

      expected_must = [
        { exists: { field: "versions" } },
        {
          bool: {
            should: [
              {
                bool: {
                  must: [
                    { terms: { owner_id: [@user_with_nothing.id] } }
                  ],
                  should: [
                    { terms: { _id: [] } },
                    {
                      bool: {
                        must: [
                          { term: { author_type: 0 } },
                          { term: { author_id: @user_with_nothing.id } }
                        ]
                      }
                    },
                    { term: { namespace: @user_with_nothing.login } },
                    { terms: { namespace: [@other_org.login] } },
                    {
                      bool: {
                        must: [
                          { match: { visibility: { query: "internal" } } },
                          { terms: { namespace: [@other_org.login] } }
                        ]
                      }
                    },
                    { term: { public: true } }
                  ],
                  minimum_should_match: 1
                }
              }
            ]
          }
        }
      ]

      expected_must_not = [
        {
          exists: {
            field: "deleted_at"
          }
        }
      ]

      assert_equal(expected_must, filter.must)
      assert_equal(expected_must_not, filter.must_not)
    end

    test "where owner is org" do
      filter = Search::Filters::RegistryFilter.new(current_user: @user_with_nothing, owner_id: @other_org.id, qualifiers: @qualifiers)
      filter.stubs(:package_ids).returns([])

      expected_must = [
        { exists: { field: "versions" } },
        {
          bool: {
            should: [
              {
                bool: {
                  must: [
                    { terms: { owner_id: [@other_org.id] } }
                  ],
                  should: [
                    { terms: { _id: [] } },
                    {
                      bool: {
                        must: [
                          { term: { author_type: 0 } },
                          { term: { author_id: @user_with_nothing.id } }
                        ]
                      }
                    },
                    { term: { namespace: @user_with_nothing.login } },
                    { terms: { namespace: [@other_org.login] } },
                    {
                      bool: {
                        must: [
                          { match: { visibility: { query: "internal" } } },
                          { terms: { namespace: [@other_org.login] } }
                        ]
                      }
                    },
                    {
                      bool: {
                        must: [
                          { term: { repo_id: @private_org_repo.id } },
                          { term: { inherit_repo_permissions: true } }
                        ]
                      }
                    },
                    { term: { public: true } }
                  ],
                  minimum_should_match: 1
                }
              }
            ]
          }
        }
      ]

      expected_must_not = [
        {
          exists: {
            field: "deleted_at"
          }
        }
      ]

      assert_equal(expected_must, filter.must)
      assert_equal(expected_must_not, filter.must_not)
    end
  end

  context "with global scope" do
    test "includes user's priviate repos" do
      filter = Search::Filters::RegistryFilter.new(current_user: @user, qualifiers: @qualifiers)

      expected_should = [
        { term: { public: true } },
        { term: { repo_id: @private_repo.id } },
        { terms: { _id: [] } },
        {
          bool: {
            must: [
              { term: { author_type: 0 } },
              { term: { author_id: @user.id } }
            ]
          }
        },
        { term: { namespace: @user.login } },
        { terms: { namespace: [@org.login] } },
        {
          bool: {
            must: [
              { match: { visibility: { query: "internal" } } },
              { terms: { namespace: [@org.login] } }
            ]
          }
        }
      ]

      expected_must_not = [
        {
          exists: {
            field: "deleted_at"
          }
        }
      ]

      assert_equal(expected_must_not, filter.must_not)
      assert_equal(expected_should, filter.should)
    end

    test "includes business id when user has no private repos" do
      business = create(:business)
      user = business.owners.first

      filter = Search::Filters::RegistryFilter.new(current_user: user, qualifiers: @qualifiers)

      expected_should = [
        { term: { public: true } },
        { term: { business_id: business.id } },
        { terms: { _id: [] } },
        {
          bool: {
            must: [
              { term: { author_type: 0 } },
              { term: { author_id: user.id } }
            ]
          }
        },
        { term: { namespace: user.login } }
      ]

      expected_must_not = [
          {
            exists: {
              field: "deleted_at"
            }
          }
        ]

      assert_equal expected_must_not, filter.must_not
      assert_equal(expected_should, filter.should)
    end

    test  "public only without a current user" do
      filter = Search::Filters::RegistryFilter.new(current_user: nil, qualifiers: @qualifiers)

      expected_should = [{ term: { public: true } }]
      expected_must_not = [
        {
          exists: {
            field: "deleted_at"
          }
        }
      ]

      assert_equal(expected_must_not, filter.must_not)
      assert_equal(expected_should, filter.should)
    end
  end

  context "with v2 namespace filters" do
    test "supports namespace filters by org" do
      @qualifiers[:org].must("dummy-org")
      filter = Search::Filters::RegistryFilter.new(current_user: @user, qualifiers: @qualifiers)

      expected_should = [
        { term: { public: true } },
        { term: { repo_id: @private_repo.id } },
        { terms: { _id: [] } },
        {
          bool: {
            must: [
              { term: { author_type: 0 } },
              { term: { author_id: @user.id } }
            ]
          }
        },
        { term: { namespace: @user.login } },
        { terms: { namespace: [@org.login] } },
        {
          bool: {
            must: [
              { match: { visibility: { query: "internal" } } },
              { terms: { namespace: [@org.login] } }
            ]
          }
        }
      ]

      expected_must_not = [
        {
          exists: {
            field: "deleted_at"
          }
        }
      ]

      assert_equal(expected_must_not, filter.must_not)
      assert_equal(expected_should, filter.should)
    end

    test "supports namespace filters by user" do
      @qualifiers[:user].must("dummy-user")
      filter = Search::Filters::RegistryFilter.new(current_user: @user, qualifiers: @qualifiers)

      expected_should = [
        { term: { public: true } },
        { term: { repo_id: @private_repo.id } },
        { terms: { _id: [] } },
        {
          bool: {
            must: [
              { term: { author_type: 0 } },
              { term: { author_id: @user.id } }
            ]
          }
        },
        { term: { namespace: @user.login } },
        { terms: { namespace: [@org.login] } },
        {
          bool: {
            must: [
              { match: { visibility: { query: "internal" } } },
              { terms: { namespace: [@org.login] } }
            ]
          }
        }
      ]

      expected_must_not = [
        {
          exists: {
            field: "deleted_at"
          }
        }
      ]

      assert_equal(expected_must_not, filter.must_not)
      assert_equal(expected_should, filter.should)
    end

    test "supports combined namespace filters" do
      @qualifiers[:org].must("dummy-org")
      @qualifiers[:user].must("dummy-user")
      filter = Search::Filters::RegistryFilter.new(current_user: @user, qualifiers: @qualifiers)

      expected_should = [
        { term: { public: true } },
        { term: { repo_id: @private_repo.id } },
        { terms: { _id: [] } },
        {
          bool: {
            must: [
              { term: { author_type: 0 } },
              { term: { author_id: @user.id } }
            ]
          }
        },
        { term: { namespace: @user.login } },
        { terms: { namespace: [@org.login] } },
        {
          bool: {
            must: [
              { match: { visibility: { query: "internal" } } },
              { terms: { namespace: [@org.login] } }
            ]
          }
        }
      ]

      expected_must_not = [
        {
          exists: {
            field: "deleted_at"
          }
        }
      ]

      assert_equal(expected_must_not, filter.must_not)
      assert_equal(expected_should, filter.should)
    end
  end

  context "edge cases" do
    test "no failure for org ID that does not exist" do
      @user.stubs(:owned_organization_ids).returns([@org.id, "99999999999999999999"])
      filter = Search::Filters::RegistryFilter.new(current_user: @user, qualifiers: @qualifiers)

      expected_should = [
        { term: { public: true } },
        { term: { repo_id: @private_repo.id } },
        { terms: { _id: [] } },
        {
          bool: {
            must: [
              { term: { author_type: 0 } },
              { term: { author_id: @user.id } }
            ]
          }
        },
        { term: { namespace: @user.login } },
        { terms: { namespace: [@org.login] } },
        {
          bool: {
            must: [
              { match: { visibility: { query: "internal" } } },
              { terms: { namespace: [@org.login] } }
            ]
          }
        }
      ]
      assert_equal expected_should, filter.should
    end

    test "capital letters in org names" do
      user = create(:user)
      org = create(:organization, admin: user, name: "CapitalOrg")

      filter = Search::Filters::RegistryFilter.new(current_user: user, qualifiers: @qualifiers)

      expected_should = [
        { term: { public: true } },
        { terms: { _id: [] } },
        {
          bool: {
            must: [
              { term: { author_type: 0 } },
              { term: { author_id: user.id } }
            ]
          }
        },
        { term: { namespace: user.login } },
        { terms: { namespace: [org.login, org.login.downcase] } },
        {
          bool: {
            must: [
              { match: { visibility: { query: "internal" } } },
              { terms: { namespace: [org.login, org.login.downcase] } }
            ]
          }
        }
      ]

      assert_equal expected_should, filter.should
    end
  end
end
