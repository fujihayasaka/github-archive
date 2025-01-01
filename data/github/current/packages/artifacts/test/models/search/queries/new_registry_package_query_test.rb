# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesNewRegistryPackageQueryTest < GitHub::TestCase
  fixtures do
    setup_search

    @user  = create(:user, login: "user", plan: "medium")
    @user2 = create(:user, login: "user2", plan: "medium")

    @user_repo = create(:repository, owner: @user, from_example: :repository_test_simple)

    @user_private_repo = create(:private_repository, owner: @user, from_example: :repository_test_simple)
    topic = create(:topic, name: "ruby")
    topic.repository_topics.create!(repository: @user_private_repo, state: :created, user: @user)

    @user2_repo = create(:repository, owner: @user2, from_example: :repository_test_simple)

    @user2_private_repo = create(:private_repository, owner: @user2, from_example: :repository_test_simple)

    @widget = make_package(@user_repo, "acme-widget")
    @cog = make_package(@user_private_repo, "acme-cog", type: "rubygems")
    @rocket = make_package(@user2_repo, "acme-rocket", summary: "Be as fast as the roadrunner", readme: "The quick brown fox")
    @secret = make_package(@user2_private_repo, "acme-secret")

  end

  setup do
    reset_cache

    @unscoped_query = Search::Queries::RegistryPackageQuery.new(current_user: @user, aggregations: true)
    @repo_scoped_query = Search::Queries::RegistryPackageQuery.new(current_user: @user, repo_id: @user_repo.id)
    @owner_scoped_query = Search::Queries::RegistryPackageQuery.new(current_user: @user, owner: @user)
    @package_type_scoped_query = Search::Queries::RegistryPackageQuery.new(current_user: @user, package_type: "rubygems")
    @anonymous_query = Search::Queries::RegistryPackageQuery.new(current_user: nil, aggregations: true)

    [@widget, @cog, @rocket, @secret].each do |package|
      make_searchable(package, type: "registry_package")
    end

    GitHub.stubs(:registry_v2_enabled_for_enterprise?).returns(true) if GitHub.enterprise?
  end

  teardown_once do
    teardown_search
  end

  def make_package(repo, name, type: "nuget", summary: nil, readme: nil)
    version = Time.now.usec
    release = create :release, repository: repo, tag_name: "v#{version}", author: repo.owner,
      state: :published, created_at: 1.month.ago, body: "*version #{version}*"

    package = Registry::Package.new name: name,
      repository_id: repo.id, registry_package_type: type, package_type: type
    version = package.package_versions.build version: "v#{version}", release: release, author: repo.owner
    version.files.build size: 1

    summary ||= "This is a summary for #{version.version}"
    version.metadata.build(name: Registry::Metadatum::KEYS[:SUMMARY], value: summary)

    readme ||= "lorem ipsum"
    version.metadata.build(name: Registry::Metadatum::KEYS[:README], value: readme)

    version.manifest = "{\"dependencies\": {\"async\":\"~1.0.0\"}}"
    package.save!

    package
  end

  context "registry_filter (new)" do
    test "anonymous (not logged in) query no search term" do
      query = @anonymous_query

      expected_document =
      {
        query: {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { exists: { field: "versions" } }
                ],
                must_not: [
                  {
                    exists: {
                      field: "deleted_at"
                    }
                  }
                ],
                should: [
                  { term: { public: true } }
                ],
                minimum_should_match: 1
              }
            }
          }
        },
        sort: [
          { "downloads" => "desc" },
          "_score"
        ],
        aggregations: {
          package_type: { terms: { field: :package_type, size: 10 } },
          package_subtype: { terms: { field: :package_subtype, size: 10 } }
        },
        _source: true,
        from: 0,
        size: 10
      }

      assert_equal(expected_document, query.query_document)
    end

    test "unscoped query" do
      query = @unscoped_query

      expected_document = {
        query: {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { exists: { field: "versions" } }
                ],
                must_not: [
                  {
                    exists: {
                      field: "deleted_at"
                    }
                  }
                ],
                should: [
                  { term: { public: true } },
                  { term: { repo_id: @user_private_repo.id } },
                  { terms: { _id: [] } },
                  {
                    bool: {
                      must: [
                        { term: { author_type: 0 } },
                        { term: { author_id: @user.id } }
                      ]
                    }
                  },
                  { term: { namespace: "user" } }
                ],
                minimum_should_match: 1
              }
            }
          }
        },
        sort: [
          { "downloads" => "desc" },
          "_score"
        ],
        aggregations: {
          package_type: { terms: { field: :package_type, size: 10 } },
          package_subtype: { terms: { field: :package_subtype, size: 10 } }
        },
        _source: true,
        from: 0,
        size: 10
      }

      assert_equal(expected_document, query.query_document)
    end

    test "repo scoped query" do
      query = @repo_scoped_query

      expected_document = {
        query: {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { exists: { field: "versions" } },
                  { terms: { repo_id: [@user_repo.id] } },
                  {
                    bool: {
                      should: [
                        {
                          bool: {
                            must: [],
                            should: [
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
                              { term: { public: true } }
                            ],
                            minimum_should_match: 1
                          }
                        },
                        {
                          bool: {
                            must: [{ term: { repo_id: @user_repo.id } }],
                            must_not: [{ exists: { field: "owner_id" } }]
                          }
                        }
                      ]
                    }
                  }
                ],
                must_not: [
                  {
                    exists: {
                      field: "deleted_at"
                    }
                  }
                ]
              }
            }
          }
        },
        sort: [
          { "downloads" => "desc" },
          "_score"
        ],
        _source: true,
        from: 0,
        size: 10
      }

      assert_equal(expected_document, query.query_document)
    end

    test "owner scoped query" do
      query = @owner_scoped_query

      expected_document = {
        query: {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { exists: { field: "versions" } },
                  {
                    bool: {
                      should: [
                        {
                          bool: {
                            must: [
                              { terms: { owner_id: [@user.id] } }
                            ],
                            should: [
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
                              { term: { public: true } }
                            ],
                            minimum_should_match: 1
                          }
                        },
                        {
                          bool: {
                            must: [{ terms: { repo_id: [@user_repo.id, @user_private_repo.id] } }],
                            must_not: [{ exists: { field: "owner_id" } }]
                          }
                        }
                      ]
                    }
                  }
                ],
                must_not: [
                  {
                    exists: {
                      field: "deleted_at"
                    }
                  }
                ]
              }
            }
          }
        },
        sort: [
          { "downloads" => "desc" },
          "_score"
        ],
        _source: true,
        from: 0,
        size: 10
      }

      assert_equal(expected_document, query.query_document)
    end

    test "package type scoped query" do
      query = @package_type_scoped_query

      expected_document = {
        query: {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { term: { package_type: "rubygems" } },
                  { exists: { field: "versions" } }
                ],
                must_not: [
                  {
                    exists: {
                      field: "deleted_at"
                    }
                  }
                ],
                should: [
                  { term: { public: true } },
                  { term: { repo_id: @user_private_repo.id } },
                  { terms: { _id: [] } },
                  {
                    bool: {
                      must: [
                        { term: { author_type: 0 } },
                        { term: { author_id: @user.id } }
                      ]
                    }
                  },
                  { term: { namespace: "user" } }
                ],
                minimum_should_match: 1
              }
            }
          }
        },
        sort: [
          { "downloads" => "desc" },
          "_score"
        ],
        _source: true,
        from: 0,
        size: 10
      }

      assert_equal(expected_document, query.query_document)
    end

    context "unscoped queries" do
      test "it will only query registry packages" do
        assert_equal("registry_package", @unscoped_query.query_params[:type])
      end

      test "searches by full name" do
        @unscoped_query.phrase = "acme-widget"
        assert_equal [@widget], @unscoped_query.execute.results.map { |result| result["_model"] }
      end

      test "searches by partial name" do
        @unscoped_query.phrase = "widget"
        assert_equal [@widget], @unscoped_query.execute.results.map { |result| result["_model"] }
      end

      test "doesn't return packages the user isn't authorized to see" do
        @unscoped_query.phrase = "acme"

        results = @unscoped_query.execute.results.map { |result| result["_model"] }
        refute_includes results, @secret
        assert_same_elements [@widget, @cog, @rocket], results
      end

      test "security_validation returns false if a private result is inadvertently returned to an anoynmous user" do
        secret_query = Search::Queries::RegistryPackageQuery.new(current_user: @user2_private_repo.owner)
        private_result = secret_query.execute.results.detect { |r| !r.dig("_source", "public") } # finds @secret
        anon_query = Search::Queries::RegistryPackageQuery.new(current_user: nil)
        refute anon_query.security_validation(private_result)
      end

      test "allows searching for other user's public packages" do
        @unscoped_query.phrase = "rocket"

        assert_equal [@rocket], @unscoped_query.execute.results.map { |result| result["_model"] }
      end

      test "allows specifying the package's owner" do
        @unscoped_query.phrase = "acme user:user2"
        assert_equal [@rocket], @unscoped_query.execute.results.map { |result| result["_model"] }
      end

      test "allows searching by package type" do
        @unscoped_query.phrase = "package_type:rubygems"
        assert_equal [@cog], @unscoped_query.execute.results.map { |result| result["_model"] }
      end

      test "allows search by visibility" do
        # creating new repository because `gauntlet` runs the test suite for 100 times and
        # this test fails from 9th attempt onwards maybe because one repo can't hold more than 10 packages (I'm not sure for this condition)
        new_private_repo = create(:private_repository, owner: @user, from_example: :repository_test_simple)
        another_private_package = make_package(new_private_repo, "foo-bar-private", type: "docker")
        make_searchable(another_private_package, type: "registry_package")
        query = Search::Queries::RegistryPackageQuery.new(current_user: @user, visibility: "private")
        assert_same_elements [@cog, another_private_package], query.execute.results.map { |result| result["_model"] }
      end

      test "allows searching by repo topic" do
        @unscoped_query.phrase = "topic:ruby"
        assert_equal [@cog], @unscoped_query.execute.results.map { |result| result["_model"] }
      end

      test "allows searching by summary" do
        @unscoped_query.phrase = "roadrunner"
        assert_equal [@rocket], @unscoped_query.execute.results.map { |result| result["_model"] }
      end

      test "allows searching by body" do
        @unscoped_query.phrase = "quick"
        assert_equal [@rocket], @unscoped_query.execute.results.map { |result| result["_model"] }
      end

      test "supports package_type aggregation" do
        @unscoped_query.phrase = "acme"
        results = @unscoped_query.execute

        assert_equal 2, results.package_types.count

        nuget = results.package_types.find { |agg| agg.term == "nuget" }
        rubygems = results.package_types.find { |agg| agg.term == "rubygems" }

        assert_equal 2, nuget.count
        assert_equal 1, rubygems.count
      end
    end

    context "repo scoped queries" do
      test "only returns packages for the specified repo" do
        @repo_scoped_query.phrase = "acme"

        assert_equal [@widget], @repo_scoped_query.execute.results.map { |result| result["_model"] }
      end
    end

    context "owner scoped queries" do
      test "only returns packages for the specified owner" do
        @owner_scoped_query.phrase = "acme"

        assert_same_elements [@widget, @cog], @owner_scoped_query.execute.results.map { |result| result["_model"] }
      end
    end

    context "package type scoped queries" do
      test "only returns packages for the specified owner" do
        @package_type_scoped_query.phrase = "acme"

        assert_same_elements [@cog], @package_type_scoped_query.execute.results.map { |result| result["_model"] }
      end
    end
  end # end registry_filter (new)
end
