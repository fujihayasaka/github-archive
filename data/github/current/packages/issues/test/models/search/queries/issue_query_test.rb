# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesIssueQueryTest < GitHub::TestCase
  fixtures do
    @defunkt = create(:staff_admin_user, login: "defunkt", plan: "medium", email: "chris@ozmm.org")
    @mojombo = create(:user, login: "mojombo", email: "tom@mojombo.com")
    @twp     = create(:user, login: "TwP", plan: "medium", email: "twp@example.com")
    @org = create(:organization, login: "myorg")
    @team = create(:team, organization: @org, privacy: :closed, name: "myteam")
    @team.add_member @defunkt
    @team.add_member @mojombo
    @bot     = create(:integration).bot

    @facebox = create(:repository, name: "facebox", owner: @defunkt)
    @grit    = create(:repository, name: "grit", owner: @mojombo)

    @facebox_issue = create :issue, repository: @facebox, user: @defunkt
    @grit_issue    = create :issue, repository: @grit, user: @mojombo
    @defunkt_on_grit_issue = create :issue, repository: @grit, user: @defunkt

    MemexHelpers.setup_organization_wide_access_for_projects("project_writer")
  end

  setup do
    @query = Search::Queries::IssueQuery.new(current_user: @defunkt, page: 1)
    GitHub::Experiment.raise_on_mismatches = false
  end

  context "#search_type_for_param" do
    test "it will query issues and pull requests by default" do
      assert_equal(%w[issue pull_request], @query.search_type_for_param)
    end

    test "but you can make it query just issues" do
      @query.phrase = "type:issue"
      assert_equal("issue", @query.search_type_for_param)
    end

    test "or just pull requests" do
      @query.phrase = "type:pr"
      assert_equal("pull_request", @query.search_type_for_param)
    end

    test "or you can be an ass" do
      @query.phrase = "type:trollololol"
      assert_equal(%w[issue pull_request], @query.search_type_for_param)
    end

    test "or you can explicitly override" do
      query = Search::Queries::IssueQuery.new(current_user: @defunkt, type: "pr", phrase: "type:issue")
      assert_equal("pull_request", query.search_type_for_param)
    end
  end

  context "query params" do
    test "includes search type in params" do
      assert_match "issues-search-test", @query.index.name
    end

    test "generates routing information" do
      @query.phrase = "search @defunkt @mojombo/grit"
      assert_match "issues-search-test", @query.index.name
    end

    test "generates no routing information for global queries" do
      query = Search::Queries::IssueQuery.new(current_user: @twp, phrase: "search")

      assert query.global?
      assert_nil query.routing
      assert_match "issues-search-test", query.index.name
    end

    test "overrides default timeout" do
      disable_feature_flag(:issue_and_pulls_search_increase_timeout)
      assert_equal "1000ms", @query.default_query_params[:timeout]
    end

    test "feature flag increases timeout" do
      enable_feature_flag(:issue_and_pulls_search_increase_timeout, @defunkt)
      assert_equal "1500ms", @query.default_query_params[:timeout]
    end
  end

  context "when building the query" do
    test "empty queries only match public repos" do
      expected = { constant_score: { filter: { bool: { must: { term: { public: true } } } } } }
      assert_equal expected, @query.build_query
    end

    test "it creates a function score string query" do
      @query.phrase = "search"
      query = @query.build_query

      assert query.key?(:bool)
      assert query[:bool][:must][:function_score]

      expected = {
        query: "search",
        fields: %w[title^1.5 body comments.body^0.8],
        phrase_slop: 10,
        default_operator: "AND",
        analyzer: "texty_search",
      }
      assert_equal expected, query[:bool][:must][:function_score][:query][:query_string]

      expected = { bool: { must: { term: { public: true } } } }
      assert_equal expected, query[:bool][:filter]
    end

    test "it escapes wildcard by default" do
      @query.phrase = "search* in:title"
      query = @query.build_query

      assert_equal("search\\*", query[:bool][:must][:function_score][:query][:query_string][:query])
    end

    test "it does not escape wildcard if escape_wildcards is set to false" do
      raw_query = Search::Queries::IssueQuery.new(escape_wildcards: false)
      raw_query.phrase = "search* in:title"
      query = raw_query.build_query

      assert_equal("search*", query[:bool][:must][:function_score][:query][:query_string][:query])
    end

    test "it does not assume that numbers are issue numbers if :in is specified" do
      @query.phrase = "search 1234 in:title"
      query = @query.build_query

      assert !query[:bool][:must].key?(:bool)

      assert_equal '"search" 1234', query[:bool][:must][:function_score][:query][:query_string][:query]

      expected = { bool: { must: { term: { public: true } } } }
      assert_equal expected, query[:bool][:filter]
    end

    test "it can be forced to search for numbers even when :in is specified" do
      raw_query = Search::Queries::IssueQuery.new(force_issue_number_terms: true)
      raw_query.phrase = "search 1234 in:title"
      query = raw_query.build_query

      # Make sure the free text portion of the query is correct.
      assert_equal(
        '"search" 1234',
        query[:bool][:must][:bool][:should][0][:function_score][:query][:query_string][:query]
      )

      # Make sure we have a number clause too.
      assert_equal(
        { term: { number: { value: 1234, boost: 100 } } },
        query[:bool][:must][:bool][:should][1]
      )
    end

    test "it does assume that numbers are issue numbers if :in is not specified" do
      @query.phrase = "search 1234"
      query = @query.build_query

      assert query[:bool][:must].key?(:bool)

      assert_equal '"search" 1234', query[:bool][:must][:bool][:should][0][:function_score][:query][:query_string][:query]

      expected = { bool: { must: { term: { public: true } } } }
      assert_equal expected, query[:bool][:filter]

      expected = { term: { number: { value: 1234, boost: 100 } } }
      assert_equal expected, query[:bool][:must][:bool][:should][1]
    end

    test "it searches for commit SHAs" do
      @query.phrase = "search ab123"
      query = @query.build_query
      assert !query[:bool][:must].key?(:bool)

      @query.phrase = "search abc1234"
      query = @query.build_query
      assert query[:bool][:must].key?(:bool)

      expected = { prefix: { commits: { value: "abc1234", boost: 100 } } }
      assert_equal expected, query[:bool][:must][:bool][:should].last

      expected = { bool: { must: { term: { public: true } } } }
      assert_equal expected, query[:bool][:filter]
    end

    test "it queries the specified fields" do
      @query.phrase = "search in:title"
      query = @query.build_query

      qs = query[:bool][:must][:function_score][:query][:query_string]
      assert_equal %w[title^1.5], qs[:fields]
    end

    test "it queries the specified fields (number)" do
      @query.phrase = "search in:number 1234"
      query = @query.build_query

      # Make sure the free text portion of the query is correct.
      assert_equal(
        '"search" 1234',
        query[:bool][:must][:bool][:should][0][:function_score][:query][:query_string][:query]
      )

      # Make sure we have a number clause too.
      assert_equal(
        { term: { number: { value: 1234, boost: 100 } } },
        query[:bool][:must][:bool][:should][1]
      )
    end

    test "it queries the number field if the number includes a hash" do
      @query.phrase = "search in:number #1234"
      query = @query.build_query

      # Make sure the free text portion of the query is correct.
      assert_equal(
        '"search" "#1234"',
        query[:bool][:must][:bool][:should][0][:function_score][:query][:query_string][:query]
      )

      # Make sure we have a number clause too.
      assert_equal(
        { term: { number: { value: 1234, boost: 100 } } },
        query[:bool][:must][:bool][:should][1]
      )
    end

    test "it queries multiple fields" do
      @query.phrase = 'search in:"title body"'
      query = @query.build_query

      qs = query[:bool][:must][:function_score][:query][:query_string]
      assert_equal %w[title^1.5 body], qs[:fields]
    end

    test "when `ngram_title: true` it adds a title.ngram to the search fields" do
      issue_query = Search::Queries::IssueQuery.new(current_user: @defunkt, page: 1, ngram_title: true)
      issue_query.phrase = "spaghetti"
      query = issue_query.build_query

      qs = query[:bool][:must][:function_score][:query][:query_string]
      assert_equal %w[title^1.5 title.ngram^0.5 body comments.body^0.8], qs[:fields]
    end

    context "with search qualifiers" do
      test "generates an archived:false filter" do
        @query.phrase = "archived:false"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { archived: false } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates an archived:true filter" do
        @query.phrase = "archived:true"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { archived: true } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates an issue type filter" do
        local_user = create(:user)
        local_org = create(:organization)
        local_org.add_member(local_user)
        repo = create(:repository, owner: local_org)

        issue_type_name = "omg what is this"
        phrase = "type:\"#{issue_type_name}\""
        query = Search::Queries::IssueQuery.new(
          phrase: phrase,
          current_user: local_user,
          repo_id: repo.id)
        expected = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { term: { issue_type_name: issue_type_name } },
                  { term: { repo_id: repo.id } },
                ],
              },
            },
          },
        }

        assert_equal expected, query.build_query
      end

      test "turns comma delimited issue-types into a should filter, allowing spaces" do
        local_user = create(:user)
        local_org = create(:organization)
        local_org.add_member(local_user)
        repo = create(:repository, owner: local_org)

        local_query = Search::Queries::IssueQuery.new(
          current_user: local_user,
          repo_id: repo.id
        )

        local_query.phrase = 'type:"type name 1","type name 2"'
        expected = { constant_score: { filter:
          { bool: { must: { term: { repo_id: repo.id } }, should: { terms: { issue_type_name: ["type name 1", "type name 2"] } }, minimum_should_match: 1 } } } }
        assert_equal expected, local_query.build_query
      end

      test "generates a parent issue filter" do
        local_user = create(:user)
        local_org = create(:organization)
        local_org.add_member(local_user)
        repo = create(:repository, owner: local_org)

        parent = "#{local_org.name}/#{repo.name}#1"
        phrase = "parent-issue:\"#{parent}\""
        query = Search::Queries::IssueQuery.new(
          phrase: phrase,
          current_user: local_user,
          repo_id: repo.id)
        expected = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { term: { parent_issue: parent } },
                  { term: { repo_id: repo.id } },
                ],
              },
            },
          },
        }

        assert_equal expected, query.build_query
      end

      test "generates a parent issue exclusion filter" do
        local_user = create(:user)
        local_org = create(:organization)
        local_org.add_member(local_user)
        repo = create(:repository, owner: local_org)

        parent = "#{local_org.name}/#{repo.name}#1"
        @query.phrase = "-parent-issue:\"#{parent}\""
        expected = { constant_score: { filter: {
          bool: {
            must: { term: { public: true } },
            must_not: { term: { parent_issue: parent } },
          },
        } } }
        assert_equal expected, @query.build_query
      end

      test "turns comma delimited parent issues into a should filter" do
        local_user = create(:user)
        local_org = create(:organization)
        local_org.add_member(local_user)
        repo = create(:repository, owner: local_org)

        local_query = Search::Queries::IssueQuery.new(
          current_user: local_user,
          repo_id: repo.id
        )

        parent1 = "#{local_org.name}/#{repo.name}#1"
        parent2 = "#{local_org.name}/#{repo.name}#2"
        local_query.phrase = "parent-issue:\"#{parent1}\",\"#{parent2}\""
        expected = { constant_score: { filter:
          { bool: { must: { term: { repo_id: repo.id } }, should: { terms: { parent_issue: [parent1, parent2] } }, minimum_should_match: 1 } } } }
        assert_equal expected, local_query.build_query
      end

      test "generates a sub-issue filter" do
        local_user = create(:user)
        local_org = create(:organization)
        local_org.add_member(local_user)
        repo = create(:repository, owner: local_org)

        sub_issue = "#{local_org.name}/#{repo.name}#1"
        phrase = "sub-issue:\"#{sub_issue}\""
        query = Search::Queries::IssueQuery.new(
          phrase: phrase,
          current_user: local_user,
          repo_id: repo.id)
        expected = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { term: { sub_issue: sub_issue } },
                  { term: { repo_id: repo.id } },
                ],
              },
            },
          },
        }

        assert_equal expected, query.build_query
      end

      test "generates a sub-issue exclusion filter" do
        local_user = create(:user)
        local_org = create(:organization)
        local_org.add_member(local_user)
        repo = create(:repository, owner: local_org)

        sub_issue = "#{local_org.name}/#{repo.name}#1"
        @query.phrase = "-sub-issue:\"#{sub_issue}\""
        expected = { constant_score: { filter: {
          bool: {
            must: { term: { public: true } },
            must_not: { term: { sub_issue: sub_issue } },
          },
        } } }
        assert_equal expected, @query.build_query
      end

      test "turns comma delimited sub-issues into a should filter" do
        local_user = create(:user)
        local_org = create(:organization)
        local_org.add_member(local_user)
        repo = create(:repository, owner: local_org)

        local_query = Search::Queries::IssueQuery.new(
          current_user: local_user,
          repo_id: repo.id
        )

        sub_issue1 = "#{local_org.name}/#{repo.name}#1"
        sub_issue2 = "#{local_org.name}/#{repo.name}#2"
        local_query.phrase = "sub-issue:\"#{sub_issue1}\",\"#{sub_issue2}\""
        expected = { constant_score: { filter:
          { bool: { must: { term: { repo_id: repo.id } }, should: { terms: { sub_issue: [sub_issue1, sub_issue2] } }, minimum_should_match: 1 } } } }
        assert_equal expected, local_query.build_query
      end

      test "generates a labels filter" do
        @query.phrase = "label:Bug label:search"

        expected = { constant_score: { filter: {
          bool: { must: [
            { bool: { must: [
              { term: { labels: "bug" } },
              { term: { labels: "search" } },
            ] } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a label exclusion filter" do
        @query.phrase = "-label:Bug -label:search"

        expected = { constant_score: { filter: {
          bool: {
            must: { term: { public: true } },
            must_not: [
              { term: { labels: "bug" } },
              { term: { labels: "search" } },
            ],
          },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a mixed label inclusion/exclusion filter" do
        @query.phrase = "label:bug -label:enterprise label:priority -label:search"

        expected = { constant_score: { filter: {
          bool: {
            must: [
              { bool: { must: [
                { term: { labels: "bug" } },
                { term: { labels: "priority" } },
              ] } },
              { term: { public: true } },
            ],
            must_not: [
              { term: { labels: "enterprise" } },
              { term: { labels: "search" } },
            ],
          },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a project filter for a repository-owned project" do
        project = create(:project)
        @query.phrase = "project:#{project.owner.name_with_owner}/#{project.number}"

        expected = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { term: { project_ids: project.id } },
                  { term: { public: true } },
                ],
              },
            },
          },
        }

        assert_equal expected, @query.build_query
      end

      test "generates a project filter for an organization-owned project" do
        org = create(:organization)
        project = create(:project, owner: org)
        org.add_member(@defunkt)

        @query.phrase = "project:#{org.login}/#{project.number}"

        expected = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { term: { project_ids: project.id } },
                  { term: { public: true } },
                ],
              },
            },
          },
        }

        assert_equal expected, @query.build_query
      end

      test "generates a project filter for an organization-owned memex project" do
        org = create(:organization)
        memex = create(:memex_project, owner: org)
        org.add_member(@defunkt)

        @query.phrase = "project:#{org.login}/#{memex.number}"

        expected = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { term: { memex_project_ids: memex.id } },
                  { term: { public: true } },
                ],
              },
            },
          },
        }

        assert_equal expected, @query.build_query
      end

      test "generates a project filter for an organization-owned project + memex project" do
        org = create(:organization)
        project = create(:project, owner: org)
        memex = create(:memex_project, owner: org)
        org.add_member(@defunkt)

        @query.phrase = "project:#{org.login}/#{project.number} project:#{org.login}/#{memex.number}"

        expected = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { bool:
                    { must: [
                      { term: { project_ids: project.id } },
                      { term: { memex_project_ids: memex.id } }
                    ]
                    }
                  },
                  { term: { public: true } },
                ],
              },
            },
          },
        }

        assert_equal expected, @query.build_query
      end

      test "generates a project filter for organization-owned projects" do
        org = create(:organization)
        projects = create_list(:project, 2, owner: org)
        org.add_member(@defunkt)

        @query.phrase = "project:#{org.login}/#{projects[0].number}"
        @query.phrase += " project:#{org.login}/#{projects[1].number}"

        expected = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { bool:
                    { must: [
                      { term: { project_ids: projects[0].id } },
                      { term: { project_ids: projects[1].id } },
                    ]
                    }
                  },
                  { term: { public: true } },
                ],
              },
            },
          },
        }

        assert_equal expected, @query.build_query
      end

      test "generates a project filter for organization-owned memex projects" do
        org = create(:organization)
        memexes = create_list(:memex_project, 2, owner: org)
        org.add_member(@defunkt)

        @query.phrase = "project:#{org.login}/#{memexes[0].number}"
        @query.phrase += " project:#{org.login}/#{memexes[1].number}"

        expected = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { bool:
                    { must: [
                      { term: { memex_project_ids: memexes[0].id } },
                      { term: { memex_project_ids: memexes[1].id } }
                    ]
                    }
                  },
                  { term: { public: true } },
                ],
              },
            },
          },
        }

        assert_equal expected, @query.build_query
      end

      test "generates a project filter for organization-owned projects + memex projects" do
        org = create(:organization)
        projects = create_list(:project, 2, owner: org)
        memexes = create_list(:memex_project, 2, owner: org)
        org.add_member(@defunkt)

        @query.phrase = "project:#{org.login}/#{projects[0].number}"
        @query.phrase += " project:#{org.login}/#{projects[1].number}"
        @query.phrase += " project:#{org.login}/#{memexes[0].number}"
        @query.phrase += " project:#{org.login}/#{memexes[1].number}"

        expected = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { bool:
                    { must: [
                      { term: { project_ids: projects[0].id } },
                      { term: { project_ids: projects[1].id } },
                      { term: { memex_project_ids: memexes[0].id } },
                      { term: { memex_project_ids: memexes[1].id } }
                    ]
                    }
                  },
                  { term: { public: true } },
                ],
              },
            },
          },
        }

        assert_equal expected, @query.build_query
      end

      test "generates an invalid filter for an inaccessible project" do
        private_repo = create(:private_repository)
        project = create(:project, owner: private_repo)
        @query.phrase = "project:#{private_repo.name_with_owner}/#{project.number}"

        expected = {
          constant_score: {
            filter: {
              bool: {
                must: { term: { public: true } },
              },
            },
          },
        }

        assert_equal expected, @query.build_query
      end

      test "generates an invalid filter for an inaccessible memex project" do
        org = create(:organization)
        memex = create(:memex_project, owner: org)
        @query.phrase = "project:#{org.login}/#{memex.number}"

        expected = {
          constant_score: {
            filter: {
              bool: {
                must: { term: { public: true } },
              },
            },
          },
        }

        assert_equal expected, @query.build_query
      end

      test "generates an invalid filter for an invalid project query" do
        private_repo = create(:private_repository)
        # this query is missing a project number and should be invalid
        @query.phrase = "project:#{private_repo.name_with_owner}"

        expected = {
          constant_score: {
            filter: {
              bool: {
                must: { term: { public: true } },
              },
            },
          },
        }

        assert_equal expected, @query.build_query
      end

      test "generates a project exclusion filter" do
        project = create(:project)
        @query.phrase = "-project:#{project.search_slug}"

        expected = {
          constant_score: {
            filter: {
              bool: {
                must: { term: { public: true } },
                must_not: { term: { project_ids: project.id } },
              },
            },
          },
        }
        assert_equal expected, @query.build_query
      end

      test "generates a project exclusion filter for memex project" do
        org = create(:organization)
        memex = create(:memex_project, owner: org)
        org.add_member(@defunkt)
        @query.phrase = "-project:#{org.login}/#{memex.number}"

        expected = {
          constant_score: {
            filter: {
              bool: {
                must: { term: { public: true } },
                must_not: { term: { memex_project_ids: memex.id } },
              },
            },
          },
        }
        assert_equal expected, @query.build_query
      end

      test "generates a project exclusion filter for classic projects" do
        org = create(:organization)
        projects = create_list(:project, 2, owner: org)
        org.add_member(@defunkt)
        @query.phrase = "-project:#{org.login}/#{projects[0].number} -project:#{org.login}/#{projects[1].number}"

        expected = {
          constant_score: {
            filter: {
              bool: {
                must: { term: { public: true } },
                must_not: {
                  bool: {
                    should: [
                      { term: { project_ids: projects[0].id } },
                      { term: { project_ids: projects[1].id } }
                    ]
                  }
                }
              }
            }
          }
        }

        assert_equal expected, @query.build_query
      end

      test "generates a project exclusion filter for memex projects" do
        org = create(:organization)
        memexes = create_list(:memex_project, 2, owner: org)
        org.add_member(@defunkt)
        @query.phrase = "-project:#{org.login}/#{memexes[0].number} -project:#{org.login}/#{memexes[1].number}"

        expected = {
          constant_score: {
            filter: {
              bool: {
                must: { term: { public: true } },
                must_not: {
                  bool: {
                    should: [
                      { term: { memex_project_ids: memexes[0].id } },
                      { term: { memex_project_ids: memexes[1].id } }
                    ]
                  }
                }
              }
            }
          }
        }

        assert_equal expected, @query.build_query
      end

      test "generates a project exclusion filter for project and memex project" do
        org = create(:organization)
        project = create(:project, owner: org)
        memex = create(:memex_project, owner: org)
        org.add_member(@defunkt)
        @query.phrase = "-project:#{org.login}/#{project.number} -project:#{org.login}/#{memex.number}"

        expected = {
          constant_score: {
            filter: {
              bool: {
                must: { term: { public: true } },
                must_not: {
                  bool: {
                    should: [
                      { term: { project_ids: project.id } },
                      { term: { memex_project_ids: memex.id } }
                    ]
                  }
                }
              }
            }
          }
        }

        assert_equal expected, @query.build_query
      end

      test "generates a classic project exclusion and memex project inclusion" do
        org = create(:organization)
        project = create(:project, owner: org)
        memex = create(:memex_project, owner: org)
        org.add_member(@defunkt)
        @query.phrase = "-project:#{org.login}/#{project.number} project:#{org.login}/#{memex.number}"

        expected = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { term: { memex_project_ids: memex.id } },
                  { term: { public: true } }
                ],
                must_not: { term: { project_ids: project.id } },
                }
              }
            }
          }

        assert_equal expected, @query.build_query
      end

      test "can generate a filter to exclude issues that appear in a memex" do
        issue = create(:issue)
        item = create(:memex_project_item, content: issue)

        raw_query = Search::Queries::IssueQuery.new(
          current_user: @defunkt,
          page: 1,
          memex_project_id: item.memex_project_id,
          repo_id: issue.repository_id
        )

        expected = {
          constant_score: {
            filter: {
              bool: {
                must: { term: { repo_id: issue.repository_id } },
                must_not: { term: { issue_id: issue.id } },
              },
            },
          },
        }
        assert_equal expected, raw_query.build_query
      end

      test "generates a milestone filter" do
        @query.phrase = "milestone:42"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { milestone_title: "42" } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a milestone title filter" do
        @query.phrase = 'milestone:"Brilliant Features"'

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { milestone_title: "brilliant features" } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a state filter" do
        @query.phrase = "state:open"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { state: "open" } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates an author filter" do
        @query.phrase = "author:defunkt"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { author_id: @defunkt.id } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates an author exclusion filter" do
        @query.phrase = "-author:defunkt -author:mojombo"

        expected = { constant_score: { filter: {
          bool: {
            must: { term: { public: true } },
            must_not: [
              { term: { author_id: @defunkt.id } },
              { term: { author_id: @mojombo.id } },
            ],
          },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a bot author filter" do
        @query.phrase = "author:#{Bot.query_filter_from_login(@bot.display_login)}"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { author_id: @bot.id } },
            { term: { public: true } },
          ] },
        } } }

        assert_equal expected, @query.build_query
      end

      test "generates a bot author exclusion filter" do
        @query.phrase = "-author:#{@bot.to_query_filter}"

        expected = { constant_score: { filter: {
          bool: {
            must: { term: { public: true } },
            must_not: { term: { author_id: @bot.id } },
          },
        } } }

        assert_equal expected, @query.build_query
      end

      test "generates an assignee filter" do
        @query.phrase = "assignee:mojombo"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { assignee_id: @mojombo.id } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a review filter" do
        @query.phrase = "review:changes-requested"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { review_status: "changes_requested" } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates an review-requested filter" do
        @query.phrase = "review-requested:mojombo"

        expected = { constant_score: { filter: {
          bool: { must: [
            { bool: { should: [
              { term: { requested_reviewer_ids: @mojombo.id } },
              { term: { requested_reviewer_team_ids: @team.id } },
              ] } },
            { term: { public: true } },
          ], must_not: { term: { author_id: @mojombo.id } } },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a user-review-requested filter" do
        @query.phrase = "user-review-requested:mojombo"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { requested_reviewer_ids: @mojombo.id } },
            { term: { public: true } },
          ], must_not: { term: { author_id: @mojombo.id } } },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates an team-review-requested filter" do
        @query.phrase = "team-review-requested:myorg/myteam"
        assert @query.valid_query?

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { requested_reviewer_team_ids: @team.id } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates an reviewed-by filter" do
        @query.phrase = "reviewed-by:mojombo"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { reviewer_ids: @mojombo.id } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a reviewed-by exclusion filter" do
        @query.phrase = "-reviewed-by:mojombo"

        expected = { constant_score: { filter: {
          bool: {
            must: { term: { public: true } },
            must_not: { term: { reviewer_ids: @mojombo.id } },
          },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a mentions filter" do
        @query.phrase = "mentions:mojombo"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { mentioned_user_ids: @mojombo.id } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a commenter filter" do
        @query.phrase = "commenter:mojombo"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { "comments.author_id" => @mojombo.id } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a created filter" do
        @query.phrase = "created:>2013-02-01"

        expected = { constant_score: { filter: {
          bool: { must: [
            { range: { created_at: { gt: "2013-02-01||/d" } } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates an updated filter" do
        @query.phrase = "updated:<2013-02-01"

        expected = { constant_score: { filter: {
          bool: { must: [
            { range: { updated_at: { lt: "2013-02-01||/d" } } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a closed filter" do
        @query.phrase = "closed:>2013-02-01"

        expected = { constant_score: { filter: {
          bool: { must: [
            { range: { closed_at: { gt: "2013-02-01||/d" } } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a number of comments filter" do
        @query.phrase = "comments:>42"

        expected = { constant_score: { filter: {
          bool: { must: [
            { range: { num_comments: { gt: "42" } } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a number of reactions filter" do
        @query.phrase = "reactions:>42"

        expected = { constant_score: { filter: {
          bool: { must: [
            { range: { num_reactions: { gt: "42" } } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a number of interactions filter" do
        @query.phrase = "interactions:>42"

        expected = { constant_score: { filter: {
          bool: { must: [
            { range: { num_interactions: { gt: "42" } } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates an owner repository filter" do
        @query.phrase = "@defunkt"

        expected = { constant_score: { filter: { bool: { must: { term: { repo_id: @facebox.id } } } } } }
        assert_equal expected, @query.build_query
      end

      test "generates a repository filter" do
        @query.phrase = "@defunkt @mojombo/grit"
        expected = { constant_score: { filter: { bool: { must: { terms: { repo_id: [@grit.id, @facebox.id] } } } } } }
        assert_equal expected, @query.build_query
      end

      test "generates a language filter" do
        @query.phrase = "language:ruby"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { language_id: 326 } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a language filter from lang:" do
        @query.phrase = "lang:ruby"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { language_id: 326 } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "handles lang: and language: together" do
        @query.phrase = "lang:ruby language:javascript"

        expected = { constant_score: { filter: {
          bool: { must: [
            { terms: { language_id: [183, 326] } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "handles lang: and language: with same language" do
        @query.phrase = "lang:ruby language:ruby"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { language_id: 326 } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a base ref filter" do
        @query.phrase = "base:master"

        expected = { constant_score: { filter: {
          bool: { must: [
            { prefix: { base_ref: "master" } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a base ref exclusion filter" do
        @query.phrase = "-base:master"

        expected = { constant_score: { filter: {
          bool: {
            must: { term: { public: true } },
            must_not: { prefix: { base_ref: "master" } },
          },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a head ref filter" do
        @query.phrase = "head:topic"

        expected = { constant_score: { filter: {
          bool: { must: [
            { prefix: { head_ref: "topic" } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a head ref exclusion filter" do
        @query.phrase = "-head:topic"

        expected = { constant_score: { filter: {
          bool: {
            must: { term: { public: true } },
            must_not: { prefix: { head_ref: "topic" } },
          },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a mixed head and base ref filter" do
        @query.phrase = "base:master base:enterprise-2-release -head:unrelated-topic"

        expected = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  {
                    bool: {
                      should: [
                        { prefix: { base_ref: "master" } },
                        { prefix: { base_ref: "enterprise-2-release" } },
                      ],
                    },
                  },
                  { term: { public: true } },
                ],
                must_not: { prefix: { head_ref: "unrelated-topic" } },
              },
            },
          },
        }
        assert_equal expected, @query.build_query
      end

      test "can search for refs case insensitive" do
        @query.phrase = "base:mAster -head:Unrelated-Topic"

        expected = { constant_score: { filter: {
          bool: {
            must: [
              { prefix: { base_ref: "master" } },
              { term: { public: true } },
            ],
            must_not: { prefix: { head_ref: "unrelated-topic" } },
          },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates an involves filter" do
        @query.phrase = "involves:defunkt"
        expected = { constant_score: { filter: {
          bool: { must: [
            { bool: { should: [
              { term: { author_id: @defunkt.id } },
              { term: { assignee_id: @defunkt.id } },
              { term: { mentioned_user_ids: @defunkt.id } },
              { term: { requested_reviewer_ids: @defunkt.id } },
              { term: { reviewer_ids: @defunkt.id } },
              { term: { "comments.author_id" => @defunkt.id } },
            ] } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query

        @query = Search::Queries::IssueQuery.new(phrase: "involves:defunkt involves:mojombo")
        expected = { constant_score: { filter: {
          bool: { must: [
            { bool: { should: [
              { terms: { author_id: [@defunkt.id, @mojombo.id] } },
              { terms: { assignee_id: [@defunkt.id, @mojombo.id] } },
              { terms: { mentioned_user_ids: [@defunkt.id, @mojombo.id] } },
              { terms: { requested_reviewer_ids: [@defunkt.id, @mojombo.id] } },
              { terms: { reviewer_ids: [@defunkt.id, @mojombo.id] } },
              { terms: { "comments.author_id" =>  [@defunkt.id, @mojombo.id] } },
            ] } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query

        @query = Search::Queries::IssueQuery.new(phrase: "-involves:mojombo")
        expected = { constant_score: { filter: {
          bool: {
            must: { term: { public: true } },
            must_not: [
              { term: { author_id: @mojombo.id } },
              { term: { assignee_id: @mojombo.id } },
              { term: { mentioned_user_ids: @mojombo.id } },
              { term: { requested_reviewer_ids: @mojombo.id } },
              { term: { reviewer_ids: @mojombo.id } },
              { term: { "comments.author_id" => @mojombo.id } },
            ],
          },
        } } }
        assert_equal expected, @query.build_query

        @query = Search::Queries::IssueQuery.new(phrase: "-involves:defunkt -involves:mojombo")
        expected = { constant_score: { filter: {
          bool: {
            must: { term: { public: true } },
            must_not: [
              { terms: { author_id: [@defunkt.id, @mojombo.id] } },
              { terms: { assignee_id: [@defunkt.id, @mojombo.id] } },
              { terms: { mentioned_user_ids: [@defunkt.id, @mojombo.id] } },
              { terms: { requested_reviewer_ids: [@defunkt.id, @mojombo.id] } },
              { terms: { reviewer_ids: [@defunkt.id, @mojombo.id] } },
              { terms: { "comments.author_id" => [@defunkt.id, @mojombo.id] } },
            ],
          },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates unique filters" do
        @query = Search::Queries::IssueQuery.new(phrase: "updated:2016-09-01..2016-09-30 comments:>50 " * 12)
        expected = { constant_score: { filter: {
          bool: {
            must: [
              { range: { updated_at: { gte: "2016-09-01||/d", lte: "2016-09-30||/d" } } },
              { range: { num_comments: { gt: "50" } } },
              { term: { public: true } },
            ],
          },
        } } }
        assert_equal expected, @query.build_query

        @query = Search::Queries::IssueQuery.new(phrase: "label:foo label:bar " * 3)
        expected = { constant_score: { filter: {
          bool: {
            must: [
              { bool: { must: [
                { term: { labels: "foo" } },
                { term: { labels: "bar" } },
              ] } },
              { term: { public: true } },
            ],
          },
        } } }
        assert_equal expected, @query.build_query
      end
    end

    context "using the `is:` qualifier" do
      test "specifies the document type to search" do
        query = Search::Queries::IssueQuery.new(phrase: "is:issue")
        query_params = query.query_params
        assert_equal({}, query_params)
        assert_match "issues", query.index.name
        refute_match "issues-search", query.index.name

        query = Search::Queries::IssueQuery.new(phrase: "is:pr")
        query_params = query.query_params
        assert_equal({}, query_params)
        assert_match "pull-requests", query.index.name

        query = Search::Queries::IssueQuery.new(phrase: "is:pull-request")
        query_params = query.query_params
        assert_equal({}, query_params)
        assert_match "pull-requests", query.index.name
      end

      test "filters on the open state" do
        @query.phrase = "is:open"
        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { state: "open" } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "filters on the closed state" do
        @query.phrase = "is:closed"
        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { state: "closed" } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "filters on the is:merged state" do
        @query.phrase = "is:merged"
        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { merged: true } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "filters on the negated is:merged state" do
        @query.phrase = "-is:merged"
        expected = { constant_score: { filter: {
          bool: {
            must: { term: { public: true } },
            must_not: { term: { merged: true } },
        } } } }
        assert_equal expected, @query.build_query
      end

      test "filters on the state:merged state" do
        @query.phrase = "state:merged"
        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { state: "merged" } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "filters on the negated state:merged state" do
        @query.phrase = "-state:merged"
        expected = { constant_score: { filter: {
          bool: {
            must: { term: { public: true } },
            must_not: { term: { state: "merged" } },
        } } } }
        assert_equal expected, @query.build_query
      end

      test "filters on the is:unmerged state" do
        @query.phrase = "is:unmerged"
        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { merged: false } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "filters on the negated is:unmerged state" do
        @query.phrase = "-is:unmerged"
        expected = { constant_score: { filter: {
          bool: {
            must: { term: { public: true } },
            must_not: { term: { merged: false } },
        } } } }
        assert_equal expected, @query.build_query
      end

      test "filters on the state:unmerged state" do
        @query.phrase = "state:unmerged"
        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { state: "unmerged" } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "filters on the negated state:unmerged state" do
        @query.phrase = "-state:unmerged"
        expected = { constant_score: { filter: {
          bool: {
            must: { term: { public: true } },
            must_not: { term: { state: "unmerged" } },
        } } } }
        assert_equal expected, @query.build_query
      end

      test "filters on the queued state" do
        @query.phrase = "is:queued"
        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { queued: true } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "filters on a negated queued state" do
        @query.phrase = "-is:queued"
        expected = { constant_score: { filter: {
          bool: {
            must: { term: { public: true } },
            must_not: { term: { queued: true }, }
          }
        } } }
        assert_equal expected, @query.build_query
      end

      test "filters on the draft state" do
        @query.phrase = "is:draft"
        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { draft: true } },
            { term: { public: true } },
          ] },
        } } }

        if GitHub.flipper[:reviewable_state_searching].enabled?(@query.current_user)
          expected = { constant_score: { filter: {
            bool: {
              must: [
                { term: { reviewable_state: "draft" } },
                { term: { public: true } }
              ]
            },
          } } }
        end
        assert_equal expected, @query.build_query
      end

      test "filters on the negated draft state" do
        @query.phrase = "-is:draft"
        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { draft: false } },
            { term: { public: true } },
          ] },
        } } }
        if GitHub.flipper[:reviewable_state_searching].enabled?(@query.current_user)
          expected = { constant_score: { filter: {
            bool: {
              must: { term: { public: true } },
              must_not: { term: { reviewable_state: "draft" } }
            },
          } } }
        end
        assert_equal expected, @query.build_query
      end

      test "does not fail over unknown draft boolean value" do
        @query.phrase = "draft:no"
        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { draft: false } },
            { term: { public: true } },
          ] },
        } } }
        if GitHub.flipper[:reviewable_state_searching].enabled?(@query.current_user)
          expected = { constant_score: { filter: {
            bool: {
              must: [{ term: { draft: false } }, { term: { reviewable_state: "draft" } }, { term: { public: true } }]
            } },
          } }
        end
        assert_equal expected, @query.build_query
      end

      test "filters on reviewable_state if user is flagged to do so" do
        enable_feature_flag(:reviewable_state_searching, @defunkt)

        @query.phrase = "is:draft"
        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { reviewable_state: "draft" } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query

        @query.phrase = "draft:true"
        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { reviewable_state: "draft" } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "does not filter on reviewable_state for anonymous users" do
        query = Search::Queries::IssueQuery.new(current_user: nil, phrase: "is:draft", page: 1)
        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { draft: true } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, query.build_query
      end

      test "filters on the public state" do
        @private = create(:private_repository, name: "github", owner: @defunkt)

        @query.phrase = "is:public"
        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { public: true } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "filters on the public state for anonymous users" do
        @query = Search::Queries::IssueQuery.new(current_user: nil)
        @private = create(:private_repository, name: "github", owner: @defunkt)

        @query.phrase = "is:public"
        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { public: true } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "filters on the private state" do
        @private = create(:private_repository, name: "github", owner: @defunkt)

        @query.phrase = "is:private"
        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { public: false } },
            { bool: { should: [
              { term: { public: true } },
              { term: { repo_id: @private.id } },
            ] } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "filters on the locked state true" do
        %w(is:locked -is:unlocked).each do |phrase|
          @query.phrase = phrase
          expected = { constant_score: { filter: {
            bool: { must: [
              { term: { locked: true } },
              { term: { public: true } },
            ] },
          } } }
          assert_equal expected, @query.build_query
        end
      end

      test "filters on the locked state false" do
        %w(is:unlocked -is:locked).each do |phrase|
          @query.phrase = phrase
          expected = { constant_score: { filter: {
            bool: { must: [
              { term: { locked: false } },
              { term: { public: true } },
            ] },
          } } }
          assert_equal expected, @query.build_query
        end
      end

      test "filters on the private state for anonymous users" do
        @query = Search::Queries::IssueQuery.new(current_user: nil)
        @private = create(:private_repository, name: "github", owner: @defunkt)

        @query.phrase = "is:private"
        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { public: false } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "unkown filters are treated as label filters" do
        @query.phrase = "is:bug"
        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { labels: "bug" } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end
    end

    context "using the `no:` filter" do
      test "filters on missing labels" do
        @query.phrase = "no:label"
        expected = { constant_score: { filter: {
          bool: {
            must: [
              { bool: { must_not: { exists: { field: :labels } } } },
              { term: { public: true } },
            ],
          },
        } } }
        assert_equal expected, @query.build_query
      end

      test "filters on missing milestones" do
        @query.phrase = "no:milestone"
        expected = { constant_score: { filter: {
          bool: { must: [
            { bool: { must_not: { exists: { field: :milestone_num } } } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "filters on missing projects" do
        @query.phrase = "no:project"

        expected = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { bool: { must_not: [{ exists: { field: :memex_project_ids } },
                                      { exists: { field: :project_ids } }] } },
                  { term: { public: true } },
                ],
              },
            },
          },
        }

        assert_equal expected, @query.build_query
      end

      test "filters on missing assignees" do
        @query.phrase = "no:assignee"
        expected = { constant_score: { filter: {
          bool: { must: [
            { bool: { must_not: { exists: { field: :assignee_id } } } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "filters on missing parent issue" do
        @query.phrase = "no:parent-issue"
        expected = { constant_score: { filter: {
          bool: { must: [
            { bool: { must_not: { exists: { field: :parent_issue } } } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "filters on missing sub-issues" do
        @query.phrase = "no:sub-issue"
        expected = { constant_score: { filter: {
          bool: { must: [
            { bool: { must_not: { exists: { field: :sub_issue } } } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end
    end

    context "using the `linked:` filter" do
      test "filters on has_closing_reference" do
        %w(linked:issue linked:pr linked:pull-request).each do |phrase|
          @query = Search::Queries::IssueQuery.new(phrase: phrase)
          expected = { constant_score: { filter: {
            bool: { must: [
              { term: { has_closing_reference: true } },
              { term: { public: true } },
            ] },
          } } }
          assert_equal expected, @query.build_query
        end
      end

      test "filters on excluding has_closing_reference" do
        %w(-linked:issue -linked:pr -linked:pull-request).each do |phrase|
          @query = Search::Queries::IssueQuery.new(phrase: phrase)
          expected = { constant_score: { filter: {
            bool: {
              must: { term: { public: true } },
              must_not: { term: { has_closing_reference: true } },
            },
          } } }
          assert_equal expected, @query.build_query
        end
      end
    end

    context "private profile users in phrase" do
      test "filtering by private profile user when viewer is the user" do
        enable_feature_flag(:invalidate_private_profile_searches)
        private_user = create(:user, private_profile: true)
        # Repo for `user:` searches
        create(:repository, owner: private_user)

        # Qualifiers
        %w(author assignee reviewed-by commenter mentions user involves review-requested user-review-requested).each do |qualifier|
          query = Search::Queries::IssueQuery.new(phrase: "#{qualifier}:#{private_user}", current_user: private_user)
          assert_predicate query, :valid_query?
        end

        # No qualifier, just the user login
        query = Search::Queries::IssueQuery.new(phrase: private_user.login, current_user: private_user)
        assert_predicate query, :valid_query?
      end

      test "filtering by private profile user when viewer is not the user" do
        enable_feature_flag(:invalidate_private_profile_searches)
        private_user = create(:user, private_profile: true)
        # Repo for `user:` searches
        create(:repository, owner: private_user)
        viewer = create(:user)

        # Qualifiers
        %w(author assignee reviewed-by commenter mentions user involves review-requested user-review-requested).each do |qualifier|
          query = Search::Queries::IssueQuery.new(phrase: "#{qualifier}:#{private_user}", current_user: viewer)
          refute_predicate query, :valid_query?
        end

        # No qualifier, just the user login
        query = Search::Queries::IssueQuery.new(phrase: private_user.login, current_user: viewer)
        assert_predicate query, :valid_query?
      end

      test "filtering by private profile user when repo_id is set" do
        enable_feature_flag(:invalidate_private_profile_searches)
        private_user = create(:user, private_profile: true)
        # Repo for `user:` searches
        repository = create(:repository, owner: private_user)

        # Qualifiers
        %w(author assignee reviewed-by commenter mentions user involves review-requested user-review-requested).each do |qualifier|
          query = Search::Queries::IssueQuery.new(phrase: "#{qualifier}:#{private_user}", current_user: private_user, repo_id: repository.id)
          assert_predicate query, :valid_query?
        end

        # No qualifier, just the user login
        query = Search::Queries::IssueQuery.new(phrase: private_user.login, current_user: private_user)
        assert_predicate query, :valid_query?
      end
    end
  end

  context "building a query with the enumerated label syntax enabled" do
    test "will turn a delimited exclusion into multiple must-not terms" do
      @query.phrase = "label:bug -label:enterprise,search label:priority"

      expected = { constant_score: { filter: {
        bool: {
          must: [
            { bool: { must: [
              { term: { labels: "bug" } },
              { term: { labels: "priority" } },
            ] } },
            { term: { public: true } },
          ],
          must_not: [
            { term: { labels: "enterprise" } },
            { term: { labels: "search" } },
          ],
        },
      } } }
      assert_equal expected, @query.build_query
    end

    test "turns comma delimited labels into a should filter" do
      @query.phrase = "label:happy,sad"
      expected = { constant_score: { filter:
        { bool: { must: { term: { public: true } }, should: { terms: { labels: %w[happy sad] } }, minimum_should_match: 1 } } } }
      assert_equal expected, @query.build_query
    end

    test "turns comma delimited labels into a should filter, allowing spaces" do
      @query.phrase = 'label:happy,"very happy"'
      expected = { constant_score: { filter:
        { bool: { must: { term: { public: true } }, should: { terms: { labels: ["happy", "very happy"] } }, minimum_should_match: 1 } } } }
      assert_equal expected, @query.build_query
    end

    test "turns comma delimited labels into a should filter with multiple other required labels" do
      @query.phrase = "label:happy,sad label:bug label:feature"
      expected = { constant_score: { filter:
        { bool: { must: [{ bool: { must: [{ term: { labels: "bug" } }, { term: { labels: "feature" } }] } }, { term: { public: true } }], should: { terms: { labels: %w[happy sad] } }, minimum_should_match: 1 } } } }
      assert_equal expected, @query.build_query
    end

    test "turns comma delimited labels into a should filter with a single required label" do
      @query.phrase = "label:happy,sad label:bug"
      expected = { constant_score: { filter:
        { bool: { must: [{ term: { labels: "bug" } }, { term: { public: true } }], should: { terms: { labels: %w[happy sad] } }, minimum_should_match: 1 } } } }
      assert_equal expected, @query.build_query
    end

    test "combines multiple delimited terms into a single must" do
      @query.phrase = "label:happy,sad label:better,worse"
      delimited_bool = { bool: { must: [
                    { bool: { should: { terms: { labels: %w[happy sad] } } } },
                    { bool: { should: { terms: { labels: %w[better worse] } } } }] } }
      expected = {
        constant_score: {
          filter: {
            bool: {
              must: [
                delimited_bool,
                { term: { public: true } }
              ]
            }
          }
        }
      }

      assert_equal expected, @query.build_query
    end

    test "appends the delimited term bool query to an existing must" do
      @query.phrase = "label:this label:happy,sad label:better,worse"

      this_term = { term: { labels: "this" } }
      delimited_bool = { bool: { must: [
                    { bool: { should: { terms: { labels: %w[happy sad] } } } },
                    { bool: { should: { terms: { labels: %w[better worse] } } } }] } }
      expected = {
        constant_score: {
          filter: {
            bool: {
              must: [
                { bool: { must: [this_term, delimited_bool] } },
                { term: { public: true } }
              ]
            }
          }
        }
      }

      assert_equal expected, @query.build_query
    end

    test "combines several label criteria together properly" do
      @query.phrase = "label:this label:that label:happy,sad label:better,worse"

      this_term = { term: { labels: "this" } }
      that_term = { term: { labels: "that" } }
      delimited_bool = { bool: { must: [
                    { bool: { should: { terms: { labels: %w[happy sad] } } } },
                    { bool: { should: { terms: { labels: %w[better worse] } } } }] } }
      expected = {
        constant_score: {
          filter: {
            bool: {
              must: [
                { bool: { must: [this_term, that_term, delimited_bool] } },
                { term: { public: true } }
              ]
            }
          }
        }
      }

      assert_equal expected, @query.build_query
    end
  end

  context "when building the highlight" do
    test "it creates some highlighting" do
      comment_body = { number_of_fragments: 1, fragment_size: Search::Queries::IssueQuery::FRAGMENT_SIZE }
      if GitHub.flipper[:unified_highlighter_for_issue_comments].enabled?
        comment_body = comment_body.merge type: "unified"
      end

      expected = {
        encoder: :html,
        fields: {
          :title => { number_of_fragments: 0 },  # force the whole title to be included in the fragment
          :body => { number_of_fragments: 1, fragment_size: Search::Queries::IssueQuery::FRAGMENT_SIZE },
          "comments.body" => comment_body,
        },
        type: "plain"
      }

      if ENV["TEST_ES_8"]
        expected[:max_analyzed_offset] = 1000000
      end

      assert_equal(expected, @query.build_highlight)
    end

    test "it only highlights the searched fields" do
      @query.phrase = "search in:title"
      expected = {
        encoder: :html,
        fields: {
          title: { number_of_fragments: 0 },
        },
        type: "plain"
      }

      if ENV["TEST_ES_8"]
        expected[:max_analyzed_offset] = 1000000
      end

      assert_equal(expected, @query.build_highlight)

      @query = Search::Queries::IssueQuery.new phrase: "search in:title,comments"
      comment_body = { number_of_fragments: 1, fragment_size: Search::Queries::IssueQuery::FRAGMENT_SIZE }
      if GitHub.flipper[:unified_highlighter_for_issue_comments].enabled?
        comment_body = comment_body.merge type: "unified"
      end

      expected = {
        encoder: :html,
        fields: {
          :title => { number_of_fragments: 0 },
          "comments.body" => comment_body,
        },
        type: "plain"
      }

      if ENV["TEST_ES_8"]
        expected[:max_analyzed_offset] = 1000000
      end

      assert_equal(expected, @query.build_highlight)
    end

    test "only if highlighting is enabled" do
      @query.phrase = "search"

      doc = @query.query_document
      assert !doc.key?(:highlight)

      @query.highlight = true
      doc = @query.query_document
      assert doc.key?(:highlight)
    end
  end

  context "when building the sort" do
    test "returns nil when the sort is empty and a query is present" do
      @query.query = "foo"
      assert_nil @query.build_sort
    end

    test "returns the default sort when the sort is empty" do
      assert_equal([{ "created_at" => { "order" => "desc", "unmapped_type" => "date" } }, "_score"], @query.build_sort)

      @query.phrase = '""'
      assert_equal([{ "created_at" => { "order" => "desc", "unmapped_type" => "date" } }, "_score"], @query.build_sort)
    end

    test "maps the sort field for comment count" do
      @query.sort = %w[comments desc]
      assert_equal([{ "num_comments" => "desc" }, "_score"], @query.build_sort)
    end

    test "maps the sort field for reaction count" do
      @query.sort = %w[reactions desc]
      assert_equal([{ "num_reactions" => "desc" }, "_score"], @query.build_sort)
    end

    test "maps the sort field for interaction count" do
      @query.sort = %w[interactions desc]
      assert_equal([{ "num_interactions" => "desc" }, "_score"],
                   @query.build_sort)
    end

    test "maps the sort field for relevance" do
      @query.sort = %w[relevance desc]
      assert_equal(["_score"], @query.build_sort)
    end

    test "accepts multiple sort fields" do
      @query.sort = %w[updated desc comments desc]
      assert_equal([{ "updated_at" => { "order" => "desc", "unmapped_type" => "date" } }, { "num_comments" => "desc" }, "_score"], @query.build_sort)
    end
  end

  context "when building the aggregations" do
    test "creates a filterless aggregation" do
      @query.aggregations = true
      @query.phrase = "label:bug"

      assert_equal [:language_id, :state], @query.aggregations

      expected = {
        language_id: { terms: { field: :language_id, size: Search::Query::per_page_default } },
        state: { terms: { field: :state, size: Search::Query::per_page_default } },
      }
      assert_equal expected, @query.build_aggregations
    end

    test "does not include a language filter" do
      @query.aggregations = true
      @query.phrase = "language:ruby"

      expected = {
        language_id: { terms: { field: :language_id, size: Search::Query::per_page_default } },
        state: {
          aggregations: { terms: { terms: { field: :state, size: Search::Query::per_page_default } } },
          filter: { bool: { must: { term: { language_id: 326 } } } },
        },
      }
      assert_equal expected, @query.build_aggregations
    end

    test "does not include a language filter with lang:" do
      @query.aggregations = true
      @query.phrase = "lang:ruby"

      expected = {
        language_id: { terms: { field: :language_id, size: Search::Query::per_page_default } },
        state: {
          aggregations: { terms: { terms: { field: :state, size: Search::Query::per_page_default } } },
          filter: { bool: { must: { term: { language_id: 326 } } } },
        },
      }
      assert_equal expected, @query.build_aggregations
    end

    test "does not include a state filter" do
      @query.aggregations = :language_id
      @query.phrase = "state:open"

      expected = {
        language_id: {
          aggregations: { terms: { terms: { field: :language_id, size: Search::Query::per_page_default } } },
          filter: { bool: { must: { term: { state: "open" } } } },
        },
      }
      assert_equal expected, @query.build_aggregations
    end
  end

  context "when created with a language" do
    test "overrides user supplied language filters" do
      query = Search::Queries::IssueQuery.new(phrase: "search language:ruby -language:perl", language: Linguist::Language["Python"])

      expected = { bool: {
        must: { function_score: {
          query: { query_string: {
            query: "search",
            fields: %w[title^1.5 body comments.body^0.8],
            phrase_slop: 10,
            default_operator: "AND",
            analyzer: "texty_search",
          } },
          score_mode: "sum",
          functions: [
            { exp: { created_at: {
              scale: "42d",
              decay: 0.5,
            } } },
            { exp: { updated_at: {
              scale: "84d",
              decay: 0.5,
            } } },
            {
              filter: { term: { state: "open" } },
              weight: 2,
            },
          ],
        } },
        filter: { bool: { must: [
          { term: { language_id: 303 } },
          { term: { public: true } },
        ] },
      } } }
      assert_equal expected, query.build_query
    end

    test "overrides user supplied language filters with lang:" do
      query = Search::Queries::IssueQuery.new(phrase: "search language:ruby -language:perl", language: Linguist::Language["Python"])

      expected = { bool: {
        must: { function_score: {
          query: { query_string: {
            query: "search",
            fields: %w[title^1.5 body comments.body^0.8],
            phrase_slop: 10,
            default_operator: "AND",
            analyzer: "texty_search",
          } },
          score_mode: "sum",
          functions: [
            { exp: { created_at: {
              scale: "42d",
              decay: 0.5,
            } } },
            { exp: { updated_at: {
              scale: "84d",
              decay: 0.5,
            } } },
            {
              filter: { term: { state: "open" } },
              weight: 2,
            },
          ],
        } },
        filter: { bool: { must: [
          { term: { language_id: 303 } },
          { term: { public: true } },
        ] },
      } } }
      assert_equal expected, query.build_query
    end
  end

  context "when created with a repository id" do
    test "overrides the normal repository filter" do
      query = Search::Queries::IssueQuery.new(phrase: "search @defunkt -@mojombo", repo_id: @grit.id)

      expected = { bool: {
        must: { function_score: {
          query: { query_string: {
            query: "search",
            fields: %w[title^1.5 body comments.body^0.8],
            phrase_slop: 10,
            default_operator: "AND",
            analyzer: "texty_search",
          } },
          score_mode: "sum",
          functions: [
            { exp: { created_at: {
              scale: "42d",
              decay: 0.5,
            } } },
            { exp: { updated_at: {
              scale: "84d",
              decay: 0.5,
            } } },
            {
              filter: { term: { state: "open" } },
              weight: 2,
            },
          ],
        } },
        filter: { bool: { must: { term: { repo_id: @grit.id } } } },
      } }
      assert_equal expected, query.build_query
    end
  end

  context "when determining whether to use a candidate repo search" do
    context "#use_candidate_repo_search?" do
      test "it returns true if a current user is present and we use a flagged search qualifier" do
        qualifier = Search::Queries::IssueQuery::CANDIDATE_REPO_SEARCH_QUALIFIERS.first
        query = Search::Queries::IssueQuery.new(phrase: "#{qualifier}:defunkt", current_user: @defunkt)
        assert_predicate query, :use_candidate_repo_search?
      end

      test "it returns true if team filter is used" do
        qualifier = :team
        query = Search::Queries::IssueQuery.new(phrase: "#{qualifier}:defunkt", current_user: @defunkt)
        assert_predicate query, :use_candidate_repo_search?
      end

      test "it returns false if a repo_id is present" do
        query = Search::Queries::IssueQuery.new(phrase: "author:defunkt", repo_id: @grit.id, current_user: @defunkt)
        refute_predicate query, :use_candidate_repo_search?
      end

      test "it returns false if there is no current_user" do
        query = Search::Queries::IssueQuery.new(phrase: "search")
        refute_predicate query, :use_candidate_repo_search?
      end

      test "it returns false if we scope to repos owned by a user" do
        query = Search::Queries::IssueQuery.new(phrase: "author:defunkt user:defunkt", current_user: @defunkt)
        refute_predicate query, :use_candidate_repo_search?
      end

      test "it returns false if we scope to repos owned by a user with owner:" do
        query = Search::Queries::IssueQuery.new(phrase: "author:defunkt owner:defunkt", current_user: @defunkt)
        refute_predicate query, :use_candidate_repo_search?
      end

      test "it returns false if we scope to repos owned by an org" do
        query = Search::Queries::IssueQuery.new(phrase: "author:defunkt org:#{@org.name}", current_user: @defunkt)
        refute_predicate query, :use_candidate_repo_search?
      end

      test "it returns false if we scope to public repos" do
        query = Search::Queries::IssueQuery.new(phrase: "author:defunkt is:public", current_user: @defunkt)
        refute_predicate query, :use_candidate_repo_search?
      end
    end
  end

  context "when validating responses" do
    test 'public field gets extracted from the "_source"' do
      assert_equal false, @query.is_public({ "_source" => { "public" => false } })
      assert_equal true, @query.is_public({ "_source" => { "public" => true } })
      assert_nil @query.is_public({ "_source" => { "no_public_field" => "booo" } })
      assert_nil @query.is_public({ "no_source_field" => "booo" })
    end

    test 'always includes the "public" field' do
      query = Search::Queries::IssueQuery.new(phrase: "search", source_fields: %w[state repo_id])
      assert_equal %w[state repo_id public updated_at], query.source_fields

      query = Search::Queries::IssueQuery.new(phrase: "search", source_fields: [])
      assert query.source_fields.include? "public"
    end
  end

  context "when executing" do
    setup do # rubocop:disable GitHub/NestedSetupTeardown
      @response = {
        "took" => 445, "timed_out" => false, "_shards" => { "total" => 3, "successful" => 3, "failed" => 0 },
        "hits" => { "total" => 596, "max_score" => nil, "hits" => [
          {
            "_index" => "issues",
            "_type" => "issue",
            "_id" => @facebox_issue.id.to_s,
            "_score" => 3.9096773,
            "_source" => { "title" => "Tabs need separator between them", "body" => "It look wkward (and not like the GTK 3) when the tabs have no separators between them.\n", "mentioned_user_ids" => [], "author_id" => 1658870, "num_comments" => 1, "num_reactions" => 1, "num_interactions" => 2, "repo_id" => @facebox.id.to_s, "network_id" => 8436977, "public" => true, "state" => "open", "number" => 3, "labels" => ["bug"], "created_at" => "2013-02-28T08:54:29-08:00", "updated_at" => "2013-02-28T09:10:52-08:00", "language_id" => 272, "comments" => [{ "comment_id" => 14244426, "body" => "Can you be more clear? And anyways, I have just started the GTK2 theme. Will notify you when it is done. Now you'll find thousands of things if you search.\n", "author_id" => 1174278, "created_at" => "2013-02-28T09:10:52-08:00", "updated_at" => "2013-02-28T09:10:52-08:00" }] },
            "highlight" => {
              "comments.body" => ["Can you be more clear? And anyways, I have just started the GTK2 theme. Will notify you when it is done. Now you'll find thousands of things if you <em>search</em>.\n"],
            },
            "sort" => [1362070469000, 3.9096773],
          }, {
            "_index" => "issues",
            "_type" => "issue",
            "_id" => @grit_issue.id.to_s,
            "_score" => 2.5102885,
            "_source" => { "title" => "Tracking: Max Gap", "body" => "If the max gap in the tracking is set to 0, there is an error. \n", "mentioned_user_ids" => [], "author_id" => 903009, "num_comments" => 1, "num_reactions" => 3, "num_interactions" => 4, "repo_id" => @grit.id.to_s, "network_id" => 2018070, "public" => true, "state" => "open", "number" => 91, "labels" => ["bug", "easy fix"], "created_at" => "2013-02-28T08:08:55-08:00", "updated_at" => "2013-02-28T09:01:22-08:00", "assignee_id" => 903009, "language_id" => 303, "comments" => [{ "comment_id" => 14241112, "body" => "The max gap is the number of past frames, the method uses in its search for the closest segmentation result. It was introduced in order to bridge \"empty images\" that sometimes happen to be acquired. \n\nTherefore, a maxgap of 0 means that the algorithm does not look into the past at all. This is logical on the one hand, but I guess that if a user wants to track, he wants the tool to look at least at t-1. Therefore, it seems reasonable to me to take instead of maxgap the max(1, maxgap). \n", "author_id" => 903009, "created_at" => "2013-02-28T08:11:17-08:00", "updated_at" => "2013-02-28T08:11:17-08:00" }] },
            "highlight" => {
              "comments.body" => ["The max gap is the number of past frames, the method uses in its <em>search</em> for the closest segmentation result. It was introduced in order to bridge &quot;empty images&quot; that sometimes happen to be acquired"],
            },
            "sort" => [1362067735000, 2.5102885],
          }, {
            "_index" => "issues",
            "_type" => "issue",
            "_id" => @defunkt_on_grit_issue.id.to_s,
            "_score" => 2.2102885,
            "_source" => { "title" => "Issue query is returning issues belonging to spammy repos", "body" => "These issues are returned, but 404 for all users but staff, and cause exceptions in GraphQL due to it's strongly-typed nature.\n", "mentioned_user_ids" => [], "author_id" => 903009, "num_comments" => 1, "num_reactions" => 3, "num_interactions" => 4, "repo_id" => @grit.id.to_s, "network_id" => 2018070, "public" => true, "state" => "open", "number" => 91, "labels" => ["bug", "easy fix"], "created_at" => "2013-02-28T08:08:55-08:00", "updated_at" => "2013-02-28T09:01:22-08:00", "assignee_id" => 903009, "language_id" => 303, "comments" => [{ "comment_id" => 14241112, "body" => "wow yes i totally agree, these shouldn't be in search", "author_id" => 903009, "created_at" => "2013-02-28T08:11:17-08:00", "updated_at" => "2013-02-28T08:11:17-08:00" }] },
            "highlight" => {
              "comments.body" => ["wow yes i totally agree, these shouldn't be in <em>search</em>"],
            },
            "sort" => [1362067735000, 2.2102885],
          }]
        },
        "aggregations" => {
          "language_id" => {
            "doc_count_error_upper_bound" => 0,
            "sum_other_doc_count" => 25,
            "buckets" => [
              { "key" => 183, "doc_count" => 159 },
              { "key" => 303, "doc_count" => 103 },
              { "key" => 181, "doc_count" => 80 },
              { "key" => 272, "doc_count" => 62 },
              { "key" => 326, "doc_count" => 42 },
              { "key" => 41, "doc_count" => 20 },
              { "key" => 43, "doc_count" => 19 },
              { "key" => 42, "doc_count" => 11 },
              { "key" => 282, "doc_count" => 9 },
              { "key" => 257, "doc_count" => 5 },
            ],
          },
        }
      }

      @index = Elastomer::Indexes::Issues.searcher
      @response["hits"] = Elastomer::UpgradeShims.shim_search_response_hits(@response["hits"]) if @index.index_running_version_8_plus?
      @index.stubs(:search).returns(@response)
      @index.stubs(:count).returns(Elastomer::UpgradeShims.get_total_hits(@response["hits"]))

      @query.instance_variable_set(:@index, @index)
    end

    test "executes the query" do
      @query.phrase = "search"
      results = @query.execute

      assert_equal @query.page, results.page
      assert_equal @query.per_page, results.per_page
      assert_equal @response["took"], results.time
      assert_equal Elastomer::UpgradeShims.get_total_hits(@response["hits"]), results.total

      first, last = results.results
      assert first.is_a?(Hash)
      assert_equal @facebox_issue, first["_model"]

      assert last.is_a?(Hash)
      assert_equal @grit_issue, last["_model"]
    end

    test "executes the count query" do
      @query.phrase = "search"
      assert_equal Elastomer::UpgradeShims.get_total_hits(@response["hits"]), @query.count
    end

    test "prunes missing issues" do
      @query.phrase = "search"
      @response["hits"]["hits"].first["_id"] = "0"

      results = @query.execute
      first = results.results.first

      assert_enqueued_jobs 1, only: RemoveFromSearchIndexJob, queue: :index_high
      assert first.is_a?(Hash)
      assert_equal @grit_issue, first["_model"]
    end

    if GitHub.spamminess_check_enabled?
      test "prunes spammy results" do
        @query.phrase = "search"
        @mojombo.update!(spammy: true)

        results = @query.execute
        first = results.results.first

        assert_enqueued_jobs 1, only: RemoveFromSearchIndexJob, queue: :index_high
        assert first.is_a?(Hash)
        assert_equal @facebox_issue, first["_model"]
      end

      test "prunes when fields has been set" do
        @response["hits"]["hits"].each { |h| h.delete("_source") }
        @query.phrase = "search"
        @query.source_fields = false
        @mojombo.update!(spammy: true)

        results = @query.execute
        first = results.results.first

        assert_enqueued_jobs 1, only: RemoveFromSearchIndexJob, queue: :index_high
        assert first.is_a?(Hash)
        assert_equal @facebox_issue, first["_model"]
      end

      test "prunes issues on repos owned by spammy users" do
        @query.phrase = "search"

        @mojombo.update!(spammy: true)
        @grit.update!(user_hidden: true)

        results = @query.execute.results

        assert_enqueued_jobs 4, only: RemoveFromSearchIndexJob, queue: :index_high

        refute results.map { |r| r["_model"] }.include?(@defunkt_on_grit_issue),
          "This issue should not be returned because it is on a spammy repo"
      end
    end
  end

  context "Parsed Query" do
    test "parse with defined fields" do
      assert_equal [[:is, "open"]],
        Search::Queries::IssueQuery.parse("is:open")
      assert_equal [[:is, "open"], "bug"],
        Search::Queries::IssueQuery.parse("is:open bug")
      assert_equal ["not:open bug"],
        Search::Queries::IssueQuery.parse("not:open bug")
    end

    test "parses enumerated labels into an array" do
      assert_equal [[:label, %w[one two]]],
      Search::Queries::IssueQuery.parse("label:one,two")
    end

    test "parses reasons" do
      assert_equal [[:reason, "completed"]], Search::Queries::IssueQuery.parse("reason:completed", @defunkt)
    end

    test "parse reason with not reason" do
      assert_equal [[:reason, ""]], Search::Queries::IssueQuery.parse("reason:", @defunkt)
    end

    test "stringify fields" do
      assert_equal "bug",
        Search::Queries::IssueQuery.stringify(["bug"])
      assert_equal "is:open bug",
        Search::Queries::IssueQuery.stringify([[:is, "open"], "bug"])
    end

    test "stringify and sort default is terms" do
      assert_equal "is:open is:issue",
        Search::Queries::IssueQuery.stringify([[:is, "open"], [:is, "issue"]])
      assert_equal "is:open is:issue",
        Search::Queries::IssueQuery.stringify([[:is, "issue"], [:is, "open"]])

      assert_equal "is:open is:pr",
        Search::Queries::IssueQuery.stringify([[:is, "open"], [:is, "pr"]])
      assert_equal "is:open is:pr",
        Search::Queries::IssueQuery.stringify([[:is, "pr"], [:is, "open"]])
    end

    test "stringify and preserve state and merged state terms" do
      assert_equal "is:open is:merged",
        Search::Queries::IssueQuery.stringify([[:is, "open"], [:is, "merged"]])
      assert_equal "is:open is:unmerged",
        Search::Queries::IssueQuery.stringify([[:is, "open"], [:is, "unmerged"]])
      assert_equal "is:closed is:merged",
        Search::Queries::IssueQuery.stringify([[:is, "closed"], [:is, "merged"]])
      assert_equal "is:closed is:unmerged",
        Search::Queries::IssueQuery.stringify([[:is, "closed"], [:is, "unmerged"]])
    end

    test "stringify and normalize duplicate terms" do
      assert_equal "is:closed",
        Search::Queries::IssueQuery.stringify([[:state, "open"], [:state, "closed"]])
      assert_equal "is:open",
        Search::Queries::IssueQuery.stringify([[:state, "open"], [:state, "closed"], [:state, "open"]])
      assert_equal "is:open sort:created-desc",
        Search::Queries::IssueQuery.stringify([[:state, "open"], [:sort, "created-asc"], [:sort, "created-desc"]])

      assert_equal "is:pr",
        Search::Queries::IssueQuery.stringify([[:type, "issue"], [:type, "pr"]])
      assert_equal "is:issue",
        Search::Queries::IssueQuery.stringify([[:type, "issue"], [:type, "pr"], [:type, "issue"]])

      assert_equal "is:unmerged",
        Search::Queries::IssueQuery.stringify([[:is, "merged"], [:is, "unmerged"]])
      assert_equal "is:merged",
        Search::Queries::IssueQuery.stringify([[:is, "unmerged"], [:is, "merged"]])

      assert_equal "author:josh",
        Search::Queries::IssueQuery.stringify([[:author, "holman"], [:author, "josh"]])

      assert_equal "assignee:josh",
        Search::Queries::IssueQuery.stringify([[:assignee, "holman"], [:assignee, "josh"]])
      assert_equal "assignee:josh",
        Search::Queries::IssueQuery.stringify([[:no, "assignee"], [:assignee, "josh"]])
      assert_equal "no:assignee",
        Search::Queries::IssueQuery.stringify([[:assignee, "holman"], [:no, "assignee"]])
      assert_equal "no:assignee",
        Search::Queries::IssueQuery.stringify([[:no, "assignee"], [:no, "assignee"]])

      assert_equal "review-requested:josh",
        Search::Queries::IssueQuery.stringify([[:"review-requested", "holman"], [:"review-requested", "josh"]])
      assert_equal "review-requested:josh",
        Search::Queries::IssueQuery.stringify([[:no, "review-requested"], [:"review-requested", "josh"]])
      assert_equal "no:review-requested",
        Search::Queries::IssueQuery.stringify([[:"review-requested", "holman"], [:no, "review-requested"]])
      assert_equal "no:review-requested",
        Search::Queries::IssueQuery.stringify([[:no, "review-requested"], [:no, "review-requested"]])

      assert_equal "reviewed-by:josh",
        Search::Queries::IssueQuery.stringify([[:"reviewed-by", "holman"], [:"reviewed-by", "josh"]])
      assert_equal "reviewed-by:josh",
        Search::Queries::IssueQuery.stringify([[:no, "reviewed-by"], [:"reviewed-by", "josh"]])
      assert_equal "-reviewed-by:josh",
        Search::Queries::IssueQuery.stringify([[:"-reviewed-by", "holman"], [:"-reviewed-by", "josh"]])
      assert_equal "-reviewed-by:josh",
        Search::Queries::IssueQuery.stringify([[:"reviewed-by", "holman"], [:"-reviewed-by", "josh"]])
      assert_equal "-reviewed-by:josh",
        Search::Queries::IssueQuery.stringify([[:no, "-reviewed-by"], [:"-reviewed-by", "josh"]])
      assert_equal "no:reviewed-by",
        Search::Queries::IssueQuery.stringify([[:"reviewed-by", "holman"], [:no, "reviewed-by"]])
      assert_equal "no:reviewed-by",
        Search::Queries::IssueQuery.stringify([[:no, "reviewed-by"], [:no, "reviewed-by"]])

      assert_equal "milestone:Issues3",
        Search::Queries::IssueQuery.stringify([[:milestone, "Issues TNG"], [:milestone, "Issues3"]])
      assert_equal "no:milestone",
        Search::Queries::IssueQuery.stringify([[:milestone, "Issues TNG"], [:no, "milestone"]])
      assert_equal "milestone:Issues3",
        Search::Queries::IssueQuery.stringify([[:no, "milestone"], [:milestone, "Issues3"]])
      assert_equal "no:milestone",
        Search::Queries::IssueQuery.stringify([[:no, "milestone"], [:no, "milestone"]])

      assert_equal "review:required",
        Search::Queries::IssueQuery.stringify([[:review, "none"], [:review, "required"]])
      assert_equal "no:review",
        Search::Queries::IssueQuery.stringify([[:review, "none"], [:no, "review"]])
      assert_equal "review:required",
        Search::Queries::IssueQuery.stringify([[:no, "review"], [:review, "required"]])
      assert_equal "no:review",
        Search::Queries::IssueQuery.stringify([[:no, "review"], [:no, "review"]])

      assert_equal "is:closed",
        Search::Queries::IssueQuery.stringify([[:is, "open"], [:is, "closed"]])
      assert_equal "is:open",
        Search::Queries::IssueQuery.stringify([[:is, "open"], [:is, "closed"], [:is, "open"]])
      assert_equal "bug author:josh is:open",
        Search::Queries::IssueQuery.stringify([[:is, "open"], "bug", [:is, "closed"], [:author, "josh"], [:is, "open"]])

      assert_equal "is:pr",
        Search::Queries::IssueQuery.stringify([[:is, "issue"], [:is, "pr"]])
      assert_equal "is:issue",
        Search::Queries::IssueQuery.stringify([[:is, "issue"], [:is, "pr"], [:is, "issue"]])

      assert_equal "is:open is:issue",
        Search::Queries::IssueQuery.stringify([[:is, "open"], [:is, "issue"]])
      assert_equal "is:open is:pr",
        Search::Queries::IssueQuery.stringify([[:is, "open"], [:is, "pr"]])
      assert_equal "is:open is:pr",
        Search::Queries::IssueQuery.stringify([[:is, "open"], [:is, "issue"], [:is, "pr"]])

      assert_equal "is:open is:issue",
        Search::Queries::IssueQuery.stringify([[:is, "open"], [:type, "issue"]])
      assert_equal "is:open is:pr",
        Search::Queries::IssueQuery.stringify([[:type, "open"], [:is, "pr"]])
      assert_equal "is:open is:pr",
        Search::Queries::IssueQuery.stringify([[:is, "open"], [:type, "issue"], [:is, "pr"]])

      assert_equal "label:bug",
        Search::Queries::IssueQuery.stringify([[:label, "bug"]])
      assert_equal "label:bug label:issues",
        Search::Queries::IssueQuery.stringify([[:label, "bug"], [:label, "issues"]])
      assert_equal "label:issues label:bug",
        Search::Queries::IssueQuery.stringify([[:label, "issues"], [:label, "bug"]])
      assert_equal "no:label",
        Search::Queries::IssueQuery.stringify([[:no, "label"]])
      assert_equal "no:label",
        Search::Queries::IssueQuery.stringify([[:no, "label"], [:no, "label"]])
      assert_equal "no:label",
        Search::Queries::IssueQuery.stringify([[:label, "bug"], [:no, "label"]])
      assert_equal "label:bug",
        Search::Queries::IssueQuery.stringify([[:no, "label"], [:label, "bug"]])
      assert_equal "label:bug label:issues",
        Search::Queries::IssueQuery.stringify([[:no, "label"], [:label, "bug"], [:label, "issues"]])

      assert_equal "draft:true is:closed",
        Search::Queries::IssueQuery.stringify([[:is, "draft"], [:is, "closed"]])
      assert_equal "draft:false is:open",
        Search::Queries::IssueQuery.stringify([[:is, "draft", true], [:is, "open"]])

      assert_equal "is:issue linked:pr",
        Search::Queries::IssueQuery.stringify([[:is, "issue"], [:linked, "issue"], [:linked, "pr"]])
    end

    test "user-review-requested and review-requested are mutually exclusive" do
      assert_equal "review-requested:josh",
        Search::Queries::IssueQuery.stringify([[:"user-review-requested", "holman"], [:"review-requested", "josh"]])
    end

    test "normalize native emoji" do
      assert_equal [[:sort, "reactions-+1-desc"]],
        Search::Queries::IssueQuery.normalize(Search::Queries::IssueQuery.parse("sort:reactions-+1-desc"))
      assert_equal [[:sort, "reactions-+1-desc"]],
        Search::Queries::IssueQuery.normalize(Search::Queries::IssueQuery.parse("sort:reactions-👍-desc"))
      assert_equal [[:sort, "reactions-heart-desc"]],
        Search::Queries::IssueQuery.normalize(Search::Queries::IssueQuery.parse("sort:reactions-heart-desc"))
      assert_equal [[:sort, "reactions-heart-desc"]],
        Search::Queries::IssueQuery.normalize(Search::Queries::IssueQuery.parse("sort:reactions-❤️-desc"))
    end

    test "normalize is:draft" do
      assert_equal [[:draft, true]],
        Search::Queries::IssueQuery.normalize(Search::Queries::IssueQuery.parse("is:draft"))
      assert_equal [[:draft, false]],
        Search::Queries::IssueQuery.normalize(Search::Queries::IssueQuery.parse("-is:draft"))
    end

    test "normalizes case for one org and repo present" do
      assert_equal [[:repo, "github/issues"], "test"],
        Search::Queries::IssueQuery.normalize(Search::Queries::IssueQuery.parse("repo:issues test org:github"))
      assert_equal [[:repo, "issues"], "test", [:org, "A"], [:org, "B"]],
        Search::Queries::IssueQuery.normalize(Search::Queries::IssueQuery.parse("repo:issues test org:A org:B"))
      assert_equal [[:repo, "A/issues"], "test", [:org, "A"]],
        Search::Queries::IssueQuery.normalize(Search::Queries::IssueQuery.parse("repo:A/issues test org:A"))
    end
  end

  test "prune_issue prunes an issue that belongs to an unsearchable repository" do
    issue = @grit_issue
    doc = { "_id" => issue.id.to_s, "_routing" => issue.repository.id.to_s }
    query = Search::Queries::IssueQuery.new

    refute query.prune_issue(doc, issue), "normal parent repo"

    issue.stubs(:parent_repo_is_searchable?).returns(false)
    assert query.prune_issue(doc, issue), "unsearchable parent repo"

    assert_enqueued_with job: RemoveFromSearchIndexJob, args: ["bulk_issues", issue.repository.id]
  end

  test "false when the repository is not active" do
    Repository.any_instance.stubs(:active?).returns(false)

    refute_predicate @grit_issue, :parent_repo_is_searchable?
  end

  test "false when the repository is spammy" do
    Repository.any_instance.stubs(:spammy?).returns(true)

    refute_predicate @grit_issue, :parent_repo_is_searchable?
  end if GitHub.spamminess_check_enabled?

  test "false when the repository is disabled" do
    Repository.any_instance.stubs(:disabled?).returns(true)

    refute_predicate @grit_issue, :parent_repo_is_searchable?
  end

  test "true when repo is eligible and can have issues" do
    assert_predicate @grit_issue, :parent_repo_is_searchable?
  end

  test "prune_pull_request prunes a pull request that belongs to an unsearchable repository" do
    pull = create(:pull_request, :disable_disk_access)
    doc = { "_id" => pull.id.to_s, "_routing" => pull.repository.id.to_s }
    query = Search::Queries::IssueQuery.new

    refute query.prune_pull_request(doc, pull), "normal repo"

    pull.stubs(:repo_is_searchable?).returns(false)

    assert query.prune_pull_request(doc, pull), "unsearchable repo"
    assert_enqueued_with job: RemoveFromSearchIndexJob, args: ["pull_request", pull.id.to_s, pull.repository.id.to_s]
  end

  test "prune_pull_request prunes a pull request that is user_hidden" do
    pull = create(:pull_request, :disable_disk_access)
    doc = { "_id" => pull.id.to_s, "_routing" => pull.repository.id.to_s }
    query = Search::Queries::IssueQuery.new

    refute query.prune_pull_request(doc, pull), "normal pr"

    pull.repository.stubs(:user_hidden).returns(true)

    assert query.prune_pull_request(doc, pull), "user_hidden pr"
    assert_enqueued_with job: RemoveFromSearchIndexJob, args: ["pull_request", pull.id.to_s, pull.repository.id.to_s]
  end

  test "prune_pull_request prunes a pull request that was created by a spammy user" do
    pull = create(:pull_request, :disable_disk_access)
    doc = { "_id" => pull.id.to_s, "_routing" => pull.repository.id.to_s }
    query = Search::Queries::IssueQuery.new

    refute query.prune_pull_request(doc, pull), "normal pr"

    pull.safe_user.stubs(:read_attribute).with(:spammy).returns(true)

    assert query.prune_pull_request(doc, pull), "spammy user pr"
    assert_enqueued_with job: RemoveFromSearchIndexJob, args: ["pull_request", pull.id.to_s, pull.repository.id.to_s]
  end

  test "prune_issue prunes an issue that is user_hidden" do
    issue = @grit_issue
    doc = { "_id" => issue.id.to_s, "_routing" => issue.repository.id.to_s }
    query = Search::Queries::IssueQuery.new

    refute query.prune_issue(doc, issue), "normal issue"

    issue.stubs(:user_hidden).returns(true)
    assert query.prune_issue(doc, issue), "user_hidden issue"

    assert_enqueued_with job: RemoveFromSearchIndexJob, args: ["issue", issue.id.to_s, issue.repository.id.to_s]
  end

  test "prune_issue prunes an issue that was created by a spammy user" do
    issue = @grit_issue
    doc = { "_id" => issue.id.to_s, "_routing" => issue.repository.id.to_s }
    query = Search::Queries::IssueQuery.new

    refute query.prune_issue(doc, issue), "normal issue"

    issue.safe_user.stubs(:read_attribute).with(:spammy).returns(true)
    assert query.prune_issue(doc, issue), "spammy user issue"

    assert_enqueued_with job: RemoveFromSearchIndexJob, args: ["issue", issue.id.to_s, issue.repository.id.to_s]
  end

  test "prune_issue does not prune an issue with a ghost owner" do
    issue = @grit_issue
    doc = { "_id" => issue.id.to_s, "_routing" => issue.repository.id.to_s }
    query = Search::Queries::IssueQuery.new

    refute query.prune_issue(doc, issue), "normal issue"

    issue.stubs(:user).returns(nil)

    assert_no_enqueued_jobs only: RemoveFromSearchIndexJob do
      refute query.prune_issue(doc, issue), "ghost owned issue"
    end
  end
end
