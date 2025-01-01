# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFiltersRegistryPackagesFilterTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @public_repo = create(:repository, owner: @user)
    @private_repo = create(:private_repository, owner: @user)

    @org = create(:organization, admin: @user)
  end

  setup do
    @qualifiers = Search::ParsedQuery.qualifiers
  end

  context "with a repository" do
    test "only includes one repository" do
      filter = Search::Filters::RegistryPackagesFilter.new(current_user: @user, repo_id: @public_repo.id, qualifiers: @qualifiers)

      expected_must = [{ term: { repo_id: @public_repo.id } }]
      expected_must_not = [
        { exists: { field: "deleted_at" } },
      ]

      assert_equal(expected_must, filter.must)
      assert_equal expected_must_not, filter.must_not
    end
  end

  context "with an owner" do
    test "where owner has repositories" do
      @qualifiers[:user].must(@user.login)
      act_as(@user)

      filter = Search::Filters::RegistryPackagesFilter.new(current_user: @user, owner_id: @user.id, qualifiers: @qualifiers)

      expected_should = [
        { terms: { repo_id: [@public_repo.id, @private_repo.id] } },
        {
          bool: {
            must: [
              { term: { owner_id: @user.id } }
            ]
          }
        }
      ]
      expected_must_not = [
        { exists: { field: "deleted_at" } },
      ]

      assert_nil filter.must
      assert_equal expected_must_not, filter.must_not
      assert_equal(expected_should, filter.should)
    end

    test "deleted repositories are not included" do
      @public_repo.update!(deleted_at: 5.minutes.ago, active: false)
      @qualifiers[:user].must(@user.login)
      act_as(@user)

      filter = Search::Filters::RegistryPackagesFilter.new(current_user: @user, owner_id: @user.id, qualifiers: @qualifiers)

      expected_should = [
        { term: { repo_id: @private_repo.id } },
        {
          bool: {
            must: [
              { term: { owner_id: @user.id } }
            ]
          }
        }
      ]
      expected_must_not = [
        { exists: { field: "deleted_at" } },
      ]

      assert_nil filter.must
      assert_equal expected_must_not, filter.must_not
      assert_equal(expected_should, filter.should)
    end

    test "where owner has no repos" do
      @qualifiers[:user].must(@org.login)

      filter = Search::Filters::RegistryPackagesFilter.new(current_user: @user, owner_id: @org.id, qualifiers: @qualifiers)

      expected_must = [
        { term: { owner_id: @org.id } },
      ]
      expected_must_not = [
        { exists: { field: "deleted_at" } },
      ]

      assert_equal(expected_must, filter.must)
      assert_equal expected_must_not, filter.must_not
    end
  end

  context "with global scope" do
    test "includes user's private repos" do
      filter = Search::Filters::RegistryPackagesFilter.new(current_user: @user, qualifiers: @qualifiers)

      expected_should = [
        {
          bool: {
            should: [
              { term: { public: true } },
              { term: { repo_id: @private_repo.id } }
            ],
          }
        },
        {
          bool: {
            must: [
              { term: { public: true } },
            ]
          }
        }
      ]
      expected_must_not = [
        { exists: { field: "deleted_at" } },
      ]

      assert_nil filter.must
      assert_equal expected_must_not, filter.must_not
      assert_equal(expected_should, filter.should)
    end

    test "includes business id when user has no private repos" do
      business = create(:business)
      user = business.owners.first

      filter = Search::Filters::RegistryPackagesFilter.new(current_user: user, qualifiers: @qualifiers)

      expected_should = [
        {
          bool: {
            should: [
              { term: { public: true } },
              { term: { business_id: business.id } }
            ],
          }
        },
        {
          bool: {
            must: [
              { term: { public: true } }
            ]
          }
        }
      ]
      expected_must_not = [
        { exists: { field: "deleted_at" } },
      ]

      assert_nil filter.must
      assert_equal expected_must_not, filter.must_not
      assert_equal(expected_should, filter.should)
    end

    test  "public only without a current user" do
      filter = Search::Filters::RegistryPackagesFilter.new(current_user: nil, qualifiers: @qualifiers)

      expected_should = { term: { public: true } }
      expected_must_not = [
        { exists: { field: "deleted_at" } },
      ]

      assert_nil filter.must
      assert_equal expected_must_not, filter.must_not
      assert_equal(expected_should, filter.should)
    end
  end

  context "with v2 namespace filters" do
    test "supports namespace filters by org" do
      @qualifiers[:org].must("dummy-org")
      filter = Search::Filters::RegistryPackagesFilter.new(current_user: @user, qualifiers: @qualifiers)

      expected_should = [
          {
              bool: {
                  should: [
                      { term: { public: true } },
                      { term: { repo_id: @private_repo.id } }
                  ],
              }
          },
          {
              bool: {
                  must: [
                      { term: { public: true } },
                      { terms: { namespace: ["dummy-org"] } }
                  ]
              }
          }
      ]

      expected_must_not = [
        { exists: { field: "deleted_at" } },
      ]

      assert_nil filter.must
      assert_equal expected_must_not, filter.must_not
      assert_equal(expected_should, filter.should)
    end

    test "supports namespace filters by user" do
      @qualifiers[:user].must("dummy-user")
      filter = Search::Filters::RegistryPackagesFilter.new(current_user: @user, qualifiers: @qualifiers)

      expected_should = [
          {
              bool: {
                  should: [
                      { term: { public: true } },
                      { term: { repo_id: @private_repo.id } }
                  ],
              }
          },
          {
              bool: {
                  must: [
                      { term: { public: true } },
                      { terms: { namespace: ["dummy-user"] } }
                  ]
              }
          }
      ]
      expected_must_not = [
        { exists: { field: "deleted_at" } },
      ]

      assert_nil filter.must
      assert_equal expected_must_not, filter.must_not
      assert_equal(expected_should, filter.should)
    end

    test "supports combined namespace filters" do
      @qualifiers[:org].must("dummy-org")
      @qualifiers[:user].must("dummy-user")
      filter = Search::Filters::RegistryPackagesFilter.new(current_user: @user, qualifiers: @qualifiers)

      expected_should = [
          {
              bool: {
                  should: [
                      { term: { public: true } },
                      { term: { repo_id: @private_repo.id } }
                  ],
              }
          },
          {
              bool: {
                  must: [
                      { term: { public: true } },
                      { terms: { namespace: %w[dummy-org dummy-user] } }
                  ]
              }
          }
      ]
      expected_must_not = [
        { exists: { field: "deleted_at" } },
      ]

      assert_nil filter.must
      assert_equal expected_must_not, filter.must_not
      assert_equal(expected_should, filter.should)
    end
  end

  context "for private profiles" do
    test "returns no must filter when user is private profile" do
      GitHub.flipper[:invalidate_private_profile_searches].enable
      private_profile = create(:user, private_profile: true)
      public_repo = create(:repository, owner: private_profile)
      private_repo = create(:private_repository, owner: private_profile)
      org = create(:organization, admin: private_profile)
      @qualifiers[:user].must(private_profile.login)

      filter = Search::Filters::RegistryPackagesFilter.new(current_user: @user, owner_id: private_profile.id, qualifiers: @qualifiers)
      expected_should = [
        {
          bool: {
            should: [
              { term: { public: true } },
              { term: { repo_id: @private_repo.id } }
            ]
          }
        },
        {
          bool: {
            must: [
              { term: { public: true } },
              { terms: { namespace: [private_profile.login] } }
            ]
          }
        }
      ]
      expected_must_not = [
        { exists: { field: "deleted_at" } }
      ]
      expected_must = [{ term: { public: true } }, { terms: { namespace: [private_profile.login] } }]

      assert_equal expected_must, filter.must
      assert_equal expected_must_not, filter.must_not
      assert_equal(expected_should, filter.should)
    end
  end
end
