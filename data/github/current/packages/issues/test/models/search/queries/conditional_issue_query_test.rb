# typed: true
# frozen_string_literal: true

require "test_helper"

class ConditionalIssueQueryTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @monalisa = create(:user, login: "monalisa")
    @searcher = create(:user, login: "searcher")
    @org = create(:organization, login: "myorg")
    @team = create(:team, organization: @org, privacy: :closed, name: "myteam")
    @team.add_member @searcher
    @team.add_member @monalisa

    @integration = create(:integration)
    @bot_user = @integration.bot

    @default_index = Elastomer::Indexes::Issues.searcher.name.freeze
    @issues_index = Elastomer::Indexes::Issues.searcher("issues" + Elastomer.env.postfix.to_s).name.freeze
    @prs_index = Elastomer::Indexes::Issues.searcher("pull-requests" + Elastomer.env.postfix.to_s).name.freeze
    @languages = {
      go: { name: "go", language_id: 132 },
      ruby: { name: "ruby", language_id: 326 },
    }.freeze

    MemexHelpers.setup_organization_wide_access_for_projects("project_writer")
  end

  setup do
    @query = Search::Queries::ConditionalIssueQuery.new(phrase: "", current_user: @searcher)
  end

  test "ensures conditional_issue search type is valid" do
    @query.execute
    assert_hydro_published_partial({ search_type: "conditional_issue" }, schema: "github.v1.Search")
  end

  context "#phrase=" do
    test "phrase is parsed into qualifiers, conditional qualifiers, and aggregation qualifiers" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:issue state:open", aggregations: true)

      assert_empty query.query

      assert query.qualifiers.has_key?(:type)
      assert query.qualifiers.has_key?(:state)

      assert query.conditional_qualifiers.is_a?(Search::ParsletQuery::BoolQualifier)
      assert_equal :and, query.conditional_qualifiers.type
      # Only is:issue is returned in conditional_qualifiers
      assert_equal 1, query.conditional_qualifiers.qualifiers.length

      # state:open is returned separately in aggregation_qualifiers
      assert_equal ["open"], query.aggregation_qualifiers[:state]&.must
    end
  end

  context "#map_to_filters" do
    test "generates elasticsearch query" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:issue state:open", aggregations: true)

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: { prefix: { _index: "issues" } }
              }
            },
          ]
        }
      }
      expected_post_filter = { bool: { must: {  term: { state: "open" } } } }

      query_document = query.query_document
      assert_equal expected_query, query_document[:query]
      assert_equal expected_post_filter, query_document[:post_filter]
    end

    test "generates elasticsearch query with implicit AND" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:issue state:open label:bug", aggregations: true)

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: [
                  { term: { labels: "bug" } },
                  { prefix: { _index: "issues" } }
                ]
              }
            },
          ]
        }
      }

      expected_post_filter = { bool: { must: { term: { state: "open" } } } }

      query_document = query.query_document
      assert_equal expected_query, query_document[:query]
      assert_equal expected_post_filter, query_document[:post_filter]
    end

    test "generates elasticsearch query with explicit AND" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:issue AND state:open AND label:bug", aggregations: true)

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: [
                  { term: { labels: "bug" } },
                  { prefix: { _index: "issues" } }
                ]
              }
            },
          ]
        }
      }

      refute query.send(:complex?)
      expected_post_filter = { bool: { must: { term: { state: "open" } } } }

      query_document = query.query_document
      assert_equal expected_query, query_document[:query]
      assert_equal expected_post_filter, query_document[:post_filter]
    end

    test "generates elasticsearch query with nested AND" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "label:track1 OR label:track2 AND archived:false state:open", aggregations: true)

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                should: [
                  {
                    bool: {
                      must: { term: { labels: "track1" } },
                    }
                  },
                  {
                    bool: {
                      must: [
                        { term: { labels: "track2" } },
                        { term: { archived: false } },
                      ]
                    }
                  }
                ]
              }
            }
          ]
        }
      }

      expected_post_filter = { bool: { must: { term: { state: "open" } } } }
      query_document = query.query_document
      assert_equal expected_query, query_document[:query]
      assert_equal expected_post_filter, query_document[:post_filter]
    end

    test "generates elasticsearch query with complex nested OR" do
      query_phrase = <<-INPUT_QUERY
      label:enhancement
      OR (
        (archived:true AND label:improvement)
        OR (archived:false AND label:bug)
      )
      state:open
      INPUT_QUERY

      query = Search::Queries::ConditionalIssueQuery.new(phrase: query_phrase, aggregations: true)

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                should: [
                  {
                    bool: {
                      must: { term: { labels: "enhancement" } }
                    }
                  },
                  {
                    bool: {
                      should: [
                        {
                          bool: {
                            must: [
                              { term: { labels: "improvement" } },
                              { term: { archived: true } },
                            ]
                          }
                        },
                        {
                          bool: {
                            must: [
                              { term: { labels: "bug" } },
                              { term: { archived: false } },
                            ]
                          }
                        }
                      ]
                    }
                  }
                ]
              }
            }
          ]
        }
      }

      assert query.send(:complex?)
      expected_post_filter = { bool: { must: { term: { state: "open" } } } }

      query_document = query.query_document
      assert_equal expected_query, query_document[:query]
      assert_equal expected_post_filter, query_document[:post_filter]
    end

    test "generates elasticsearch query with complex nested AND" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "label:enhancement OR ((archived:true OR label:improvement) AND (archived:false OR label:bug)) state:open", aggregations: true)

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                should: [
                  {
                    bool: {
                      must:  { term: { labels: "enhancement" } },
                    }
                  },
                  {
                    bool: {
                      must: [
                        {
                          bool: {
                            should: [
                              { terms: { labels: ["improvement"] } },
                              { term: { archived: true } },
                            ],
                            minimum_should_match: 1,
                          }
                        },
                        {
                          bool: {
                            should: [
                              { terms: { labels: ["bug"] } },
                              { term: { archived: false } },
                            ],
                            minimum_should_match: 1,
                          }
                        }
                      ]
                    }
                  }
                ],
              }
            },
          ]
        }
      }

      expected_post_filter = { bool: { must: { term: { state: "open" } } } }

      query_document = query.query_document
      assert_equal expected_query, query_document[:query]
      assert_equal expected_post_filter, query_document[:post_filter]
    end

    test "generates elasticsearch query with complex nested negative qualifier" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "label:enhancement OR (label:documentation AND -label:bug)")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                should: [
                  {
                    bool: {
                      must: { term: { labels: "enhancement" } },
                    }
                  },
                  {
                    bool: {
                      must: { term: { labels: "documentation" } },
                      must_not: { term: { labels: "bug" } }
                    }
                  }
                ]
              }
            },
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "generates correct elasticsearch query when suffixed by top level fields" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "label:a OR label:b sort:created-at", current_user: @searcher)

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                should: {
                  terms: { labels: %w(a b) },
                },
                minimum_should_match: 1,
              }
            },
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "generates correct negated OR elasticsearch query when suffixed by top level fields" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "-label:a OR -label:b sort:created-at", current_user: @searcher)

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must_not: {
                  bool: {
                    must: [
                      { term: { labels: "a" } },
                      { term: { labels: "b" } },
                    ]
                  }
                }
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "generates correct negated OR elasticsearch query when a no filter is used with a positive filter" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "milestone:sprint1 OR no:milestone", current_user: @searcher)
      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                should: [
                  {
                    bool: { must: { term: { milestone_title: "sprint1" } } },
                  },
                  {
                    bool: {
                      must: {
                        bool: {
                          must_not: { exists: { field: :milestone_num } }
                        }
                      },
                    },
                  },
                ],
              },
            },
          ],
        }
      }
      assert_equal expected_query, query.build_query_filter
    end

    context "#qualifier_to_query" do
      test "generates a single term query doc" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "search", current_user: @searcher).build_query

        expected = {
          bool: {
            must: [
              { term: { public: true } },
              {
                function_score: {
                  query: {
                    query_string: {
                      query: "search",
                      fields: %w[title^1.5 body comments.body^0.8],
                      phrase_slop: 10,
                      default_operator: "AND",
                      analyzer: "texty_search",
                    }
                  },
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
                  ]
                }
              },
            ]
          }
        }

        assert_equal expected, query
      end

      test "generates a multi-term query doc" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "search term", current_user: @searcher).build_query

        expected = {
          query: "search term",
          fields: %w[title^1.5 body comments.body^0.8],
          phrase_slop: 10,
          default_operator: "AND",
          analyzer: "texty_search",
        }

        assert_equal expected, query[:bool][:must][1][:function_score][:query][:query_string]
      end

      test "generates a sha query if a commit hash is identified in a search term" do
        commit_sha = "e1109ab"
        query = Search::Queries::ConditionalIssueQuery.new(phrase: commit_sha).build_query

        expected_function_term = {
          function_score: {
            query: {
              query_string: {
                query: commit_sha,
                fields: ["title^1.5", "body", "comments.body^0.8"],
                phrase_slop: 10,
                default_operator: "AND",
                analyzer: "texty_search"
              }
            },
            score_mode: "sum",
            functions: [
              { exp: { created_at: { scale: "42d", decay: 0.5 } } },
              { exp: { updated_at: { scale: "84d", decay: 0.5 } } },
              {
                filter: { term: { state: "open" } },
                weight: 2,
              }
            ]
          }
        }

        expected_prefix_term = {
          prefix: {
            commits: {
              value: commit_sha,
              boost: 100,
            }
          }
        }

        sha_terms = query[:bool][:must][1][:bool][:should]
        function_term = sha_terms[0]
        assert_equal expected_function_term, function_term

        prefix_term = sha_terms[1]
        assert_equal expected_prefix_term, prefix_term
      end

      test "generates a term and filter query doc" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "label:bug search", current_user: @searcher).build_query

        expected = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: [
                    {
                      function_score: {
                        query: {
                          query_string: {
                            query: "search",
                            fields: %w[title^1.5 body comments.body^0.8],
                            phrase_slop: 10,
                            default_operator: "AND",
                            analyzer: "texty_search",
                          }
                        },
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
                        ]
                      }
                    },
                    {
                      bool: {
                        must: { term: { labels: "bug" } },
                      }
                    },
                  ]
                }
              }
            ]
          }
        }

        assert_equal expected, query
      end

      test "only searches in title when in:title is used" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "search in:title", current_user: @searcher).build_query

        expected = {
          bool: {
            must: [
              { term: { public: true } },
              {
                function_score: {
                  query: {
                    query_string: {
                      query: "search",
                      fields: %w[title^1.5],
                      phrase_slop: 10,
                      default_operator: "AND",
                      analyzer: "texty_search",
                    }
                  },
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
                  ]
                }
              },
            ]
          }
        }

        assert_equal expected, query
      end

      test "only searches in body when in:body is used" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "search in:body", current_user: @searcher).build_query

        expected = {
          bool: {
            must: [
              { term: { public: true } },
              {
                function_score: {
                  query: {
                    query_string: {
                      query: "search",
                      fields: %w[body],
                      phrase_slop: 10,
                      default_operator: "AND",
                      analyzer: "texty_search",
                    }
                  },
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
                  ]
                }
              },
            ]
          }
        }

        assert_equal expected, query
      end

      test "only searches in comments when in:comments is used" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "search in:comments", current_user: @searcher).build_query

        expected = {
          bool: {
            must: [
              { term: { public: true } },
              {
                function_score: {
                  query: {
                    query_string: {
                      query: "search",
                      fields: %w[comments.body^0.8],
                      phrase_slop: 10,
                      default_operator: "AND",
                      analyzer: "texty_search",
                    }
                  },
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
                  ]
                }
              },
            ]
          }
        }

        assert_equal expected, query
      end

      test "double quoted terms restrict the phrase slop to support exact matches" do
        query_input = "\"version 1.0\" 'depends on' bug missing in:title"
        query = Search::Queries::ConditionalIssueQuery.new(phrase: query_input, current_user: @searcher).build_query

        expected_exact_slop = 0
        expected_exact_analyzer = "texty"
        expected_non_exact_slop = 10
        expected_non_exact_analyzer = "texty_search"

        expected = {
          bool: {
            must: [
              { term: { public: true } },
              {
                function_score: {
                  query: {
                    query_string: {
                      query: '"version 1.0" "depends on" bug missing',
                      fields: %w[title^1.5],
                      phrase_slop: expected_exact_slop,
                      default_operator: "AND",
                      analyzer: expected_exact_analyzer,
                    },
                  },
                  score_mode: "sum",
                  functions: [
                    { exp: { created_at: { scale: "42d", decay: 0.5 } } },
                    { exp: { updated_at: { scale: "84d", decay: 0.5 } } },
                    { filter: { term: { state: "open" } }, weight: 2 },
                  ],
                },
              },
            ],
          },
        }

        assert_equal expected, query
      end

      test "NOT query term" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "NOT bootstrap", current_user: @searcher).build_query

        expected = {
          bool: {
            must: [
              { term: { public: true } },
              {
                function_score: {
                  query: {
                    query_string: {
                      query: "NOT bootstrap",
                      fields: %w[title^1.5 body comments.body^0.8],
                      phrase_slop: 10,
                      default_operator: "AND",
                      analyzer: "texty_search"
                    }
                  },
                  score_mode: "sum",
                  functions: [
                    { exp: { created_at: {
                      scale: "42d",
                      decay: 0.5
                    } } },
                    { exp: { updated_at: {
                      scale: "84d",
                      decay: 0.5
                    } } },
                    { filter: { term: { state: "open" } },
                    weight: 2
                    }
                  ]
                }
              }
            ]
          }
        }

        assert_equal expected, query
      end

      test "NOT query term in field" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "NOT bootstrap in:body", current_user: @searcher).build_query

        expected = {
          bool: {
            must: [
              { term: { public: true } },
              {
                function_score: {
                  query: {
                    query_string: {
                      query: "NOT bootstrap",
                      fields: %w[body],
                      phrase_slop: 10,
                      default_operator: "AND",
                      analyzer: "texty_search"
                    }
                  },
                  score_mode: "sum",
                  functions: [
                    { exp: { created_at: {
                      scale: "42d",
                      decay: 0.5
                    } } },
                    { exp: { updated_at: {
                      scale: "84d",
                      decay: 0.5
                    } } },
                    { filter: { term: { state: "open" } },
                    weight: 2
                    }
                  ]
                }
              }
            ]
          }
        }

        assert_equal expected, query
      end
    end

    context "generates elasticsearch query for field-specific filters" do
      context "repository" do
        test "can view public repositories without repo filter" do
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "label:a", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: { term: { labels: "a" } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "can view public repositories with repo filter" do
          repo = create(:repository)
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "repo:#{repo.name_with_owner}", current_user: @searcher)

          expected_query = {
            bool: {
              must: { term: { repo_id: repo.id } },
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "can view multiple public repositories with repo filter" do
          first_repo = create(:repository)
          second_repo = create(:repository)
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "repo:#{first_repo.name_with_owner} repo:#{second_repo.name_with_owner}", current_user: @searcher)

          expected_query = {
            bool: {
              must: { terms: { repo_id: [first_repo.id, second_repo.id] } },
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        # This test is demonstrating that we currently combine all `repo:` filters into a single value. This is a known
        # limitation and needs to be addressed in a follow-up as part of:
        # https://github.com/github/collaboration-workflows-flex/issues/751
        test "can view public repositories with repo filter in different groups" do
          first_repo = create(:repository)
          second_repo = create(:repository)
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "(label:a AND repo:#{first_repo.name_with_owner}) OR (label:b AND repo:#{second_repo.name_with_owner})", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { terms: { repo_id: [first_repo.id, second_repo.id] } },
                {
                  bool: {
                    should: { terms: { labels: %w(a b) } },
                    minimum_should_match: 1,
                  }
                }
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "can view public repositories with user filter" do
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "user:#{@searcher.login}", current_user: @searcher)

          expected_query = {
            bool: {
              must: { term: { public: true } },
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        # This test is demonstrating that we currently combine all `repo:` filters into a single value. This is a known
        # limitation and needs to be addressed in a follow-up as part of:
        # https://github.com/github/collaboration-workflows-flex/issues/751
        test "can view public repositories with user filter in different groups" do
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "(label:a AND user:#{@searcher.login}) OR (label:b AND user:#{@searcher.login})", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    should: { terms: { labels: %w(a b) } },
                    minimum_should_match: 1,
                  }
                }
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "cannot view private repos user doesn't have access to with repo filter" do
          repo = create(:private_repository)
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "repo:#{repo.name_with_owner}", current_user: @searcher)

          expected_query = {
            bool: {
              must: { term: { public: true } },
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "cannot view private repos user doesn't have access to with user filter" do
          repo = create(:private_repository)
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "user:#{repo.owner.login}", current_user: @searcher)

          expected_query = {
            bool: {
              must: { term: { public: true } },
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "can view private repos user does have access to with repo filter" do
          repo = create(:private_repository, owner: @searcher)
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "repo:#{repo.name_with_owner}", current_user: @searcher)

          expected_query = {
            bool: {
              must: { term: { repo_id: repo.id } },
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "can view private repos user does have access to with multiple repo filters" do
          first_repo = create(:private_repository, owner: @searcher)
          second_repo = create(:private_repository, owner: @searcher)
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "repo:#{first_repo.name_with_owner} repo:#{second_repo.name_with_owner}", current_user: @searcher)

          expected_query = {
            bool: {
              must: { terms: { repo_id: [first_repo.id, second_repo.id] } },
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "can view private repos user does have access to with user filter" do
          repo = create(:private_repository, owner: @searcher)
          act_as(@searcher)
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "user:#{@searcher.login}", current_user: @searcher)

          expected_query = {
            bool: {
              must: { term: { repo_id: repo.id } },
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "can view multiple private repos user does have access to with user filter" do
          repo_one = create(:private_repository, owner: @searcher)
          repo_two = create(:private_repository, owner: @searcher)
          act_as(@searcher)
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "user:#{@searcher.login}", current_user: @searcher)

          expected_query = {
            bool: {
              must: { terms: { repo_id: [repo_one.id, repo_two.id] } },
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "handles a top level public repository with a nested search" do
          repo = create(:repository)
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "(label:bug OR label:fixed) repo:#{repo.name_with_owner}", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { repo_id: repo.id } },
                {
                  bool: {
                    should: { terms: { labels: %w(bug fixed) } },
                    minimum_should_match: 1,
                  }
                }
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end
      end

      test "status" do
        status_possible_values = %w(pending success failure)
        status_possible_values.each do |status_value|
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "status:#{status_value}", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: { term: { status: status_value } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end
      end

      test "author" do
        user = @monalisa
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "author:#{user.display_login}", current_user: @searcher)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: { term: { author_id: user.id } },
                }
              },
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "bot author" do
        bot_login = @bot_user.display_login.chomp("[bot]")
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "author:app/#{bot_login}", current_user: @searcher)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: { term: { author_id: @bot_user.id } },
                }
              },
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      context "assignee" do
        test "assignee" do
          user = @monalisa
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "assignee:#{user.display_login}", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: { term: { assignee_id: user.id } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "has:assignee" do
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "has:assignee", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: {
                      exists: { field: :assignee_id }
                    }
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "has:project" do
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "has:project", current_user: @searcher)


          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: {
                      bool: {
                        should: [
                          { exists: { field: "project_ids" } },
                          { exists: { field: "memex_project_ids" } },
                        ]
                      }
                    }
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "no:assignee" do
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "no:assignee", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: {
                      bool: {
                        must_not: {
                          exists: { field: :assignee_id }
                        }
                      }
                    }
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end
      end

      test "mentions" do
        user = @monalisa
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "mentions:#{user.display_login}", current_user: @searcher)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: { term: { mentioned_user_ids: user.id } },
                }
              },
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "commenter" do
        user = @monalisa
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "commenter:#{user.display_login}", current_user: @searcher)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: { term: { "comments.author_id" => user.id } },
                }
              },
            ]
          }
        }
        assert_equal expected_query, query.build_query_filter
      end

      test "involves" do
        user = @monalisa
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "involves:#{user.display_login}", current_user: @searcher)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: {
                    bool: {
                      should: [
                        { term: { author_id: user.id } },
                        { term: { assignee_id: user.id } },
                        { term: { mentioned_user_ids: user.id } },
                        { term: { requested_reviewer_ids: user.id } },
                        { term: { reviewer_ids: user.id } },
                        { term: { "comments.author_id" => user.id } },
                      ]
                    }
                  }
                }
              },
            ]
          }
        }
        assert_equal expected_query, query.build_query_filter
      end

      context "milestone" do
        test "milestone" do
          milestone = create(:milestone, title: "test milestone")
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "milestone:\"#{milestone.title}\"", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: { term: { milestone_title: milestone.title } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "has:milestone" do
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "has:milestone", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: {
                      exists: { field: :milestone_num }
                    }
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "no:milestone" do
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "no:milestone", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: {
                      bool: {
                        must_not: {
                          exists: { field: :milestone_num }
                        }
                      }
                    }
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "milestone:none" do
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "milestone:none", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: {
                      bool: {
                        must_not: {
                          exists: { field: :milestone_num }
                        }
                      }
                    }
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "milestone:any" do
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "milestone:any", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: { exists: { field: :milestone_num } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "milestone:*" do
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "milestone:*", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: { exists: { field: :milestone_num } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "multiple milestones with OR" do
          first_milestone = create(:milestone, title: "first milestone")
          second_milestone = create(:milestone, title: "second milestone")
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "milestone:\"#{first_milestone.title}\" OR milestone:\"#{second_milestone.title}\"", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    should: {
                      terms: { milestone_title: [first_milestone.title, second_milestone.title] }
                    },
                    minimum_should_match: 1,
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end
      end

      test "language" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "language:#{@languages[:ruby][:name]}", current_user: @searcher)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: { term: { language_id: @languages[:ruby][:language_id] } },
                },
              },
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "multiple language fields" do
        query = Search::Queries::ConditionalIssueQuery.new(
          phrase: "lang:#{@languages[:ruby][:name]} AND lang:#{@languages[:go][:name]}",
          current_user: @searcher
        )

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: {
                    bool: {
                      must: [
                        { term: { language_id: @languages[:ruby][:language_id] } },
                        { term: { language_id: @languages[:go][:language_id] } },
                      ],
                    },
                  },
                },
              },
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "multiple lang fields with OR" do
        query = Search::Queries::ConditionalIssueQuery.new(
          phrase: "lang:#{@languages[:ruby][:name]} OR lang:#{@languages[:go][:name]}",
          current_user: @searcher
        )

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  should: {
                    terms: { language_id: [@languages[:ruby][:language_id], @languages[:go][:language_id]]  }
                  },
                  minimum_should_match: 1,
                },
              },
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "multiple language fields with OR" do
        query = Search::Queries::ConditionalIssueQuery.new(
          phrase: "language:#{@languages[:ruby][:name]} OR language:#{@languages[:go][:name]}",
          current_user: @searcher
        )

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  should: {
                    terms: { language_id: [@languages[:ruby][:language_id], @languages[:go][:language_id]]  }
                  },
                  minimum_should_match: 1,
                },
              },
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      context "team" do
        test "single team filter" do
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "team:#{@org.name}/#{@team.name}", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: { term: { mentioned_team_ids: @team.id } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "multiple team filters with implicit AND" do
          other_team = create(:team, organization: @org, privacy: :closed, name: "otherteam")
          other_team.add_member @searcher

          query = Search::Queries::ConditionalIssueQuery.new(phrase: "team:#{@org.name}/#{@team.name} team:#{@org.name}/#{other_team.name}", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: {
                      bool: {
                        must: [
                          { term: { mentioned_team_ids: @team.id } },
                          { term: { mentioned_team_ids: other_team.id } },
                        ],
                      }
                    }
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "multiple team filters with explicit AND" do
          other_team = create(:team, organization: @org, privacy: :closed, name: "otherteam")
          other_team.add_member @searcher

          query = Search::Queries::ConditionalIssueQuery.new(phrase: "team:#{@org.name}/#{@team.name} AND team:#{@org.name}/#{other_team.name}", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: {
                      bool: {
                        must: [
                          { term: { mentioned_team_ids: @team.id } },
                          { term: { mentioned_team_ids: other_team.id } },
                        ],
                      }
                    }
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "multiple team filters with explicit OR" do
          other_team = create(:team, organization: @org, privacy: :closed, name: "otherteam")
          other_team.add_member @searcher

          query = Search::Queries::ConditionalIssueQuery.new(phrase: "team:#{@org.name}/#{@team.name} OR team:#{@org.name}/#{other_team.name}", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    should: { terms: { mentioned_team_ids: [@team.id, other_team.id] } },
                    minimum_should_match: 1,
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end
      end

      context "PR review fields" do
        test "review:{value}" do
          possible_values = %w(none required approved changes_requested)
          possible_values.each do |test_value|
            query = Search::Queries::ConditionalIssueQuery.new(phrase: "review:#{test_value}", current_user: @searcher)

            expected_query = {
              bool: {
                must: [
                  { term: { public: true } },
                  {
                    bool: {
                      must: { term: { review_status: test_value } },
                    }
                  },
                ]
              }
            }

            assert_equal expected_query, query.build_query_filter
          end
        end

        test "reviewed-by" do
          user = @monalisa
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "reviewed-by:#{user.display_login}", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: { term: { reviewer_ids: user.id } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "review-requested" do
          user = @monalisa
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "review-requested:#{user.display_login}", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: {
                      bool: {
                        should: [
                          { term: { requested_reviewer_ids: user.id } },
                          { term: { requested_reviewer_team_ids: @team.id } }
                        ]
                      }
                    },
                    must_not: { term: { author_id: user.id } }
                  }
                },
              ],
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "review-requested explicit, implicit AND" do
          user1 = @monalisa
          user2 = @searcher
          query_implicit_and = Search::Queries::ConditionalIssueQuery.new(phrase: "review-requested:#{user1.display_login} review-requested:#{user2.display_login}", current_user: @searcher)
          query_explicit_and = Search::Queries::ConditionalIssueQuery.new(phrase: "review-requested:#{user1.display_login} AND review-requested:#{user2.display_login}", current_user: @searcher)

          assert_equal query_implicit_and.build_query_filter, query_explicit_and.build_query_filter
        end

        test "user-review-requested" do
          user = @monalisa
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "user-review-requested:#{user.display_login}", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: { term: { requested_reviewer_ids: user.id } },
                    must_not: { term: { author_id: user.id } }
                  }
                },
              ],
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "only use review-requested when used together with user-review-requested" do
          user = @monalisa
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "user-review-requested:#{user.display_login} review-requested:#{user.display_login}", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: {
                      bool: {
                        should: [
                          { term: { requested_reviewer_ids: user.id } },
                          { term: { requested_reviewer_team_ids: @team.id } }
                        ]
                      }
                    },
                    must_not: { term: { author_id: user.id } }
                  }
                },
              ],
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "team-review-requested" do
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "team-review-requested:#{@org.name}/#{@team.name}", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: { term: { requested_reviewer_team_ids: @team.id } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end
      end

      context "locked" do
        test "locked true" do
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:locked", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: { term: { locked: true } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "locked false" do
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:unlocked", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: { term: { locked: false } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end
      end

      context "merged_state" do
        test "merged_state true" do
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:merged", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: { term: { merged: true } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "merged_state false" do
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:unmerged", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: { term: { merged: false } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end
      end

      context "owner" do
        test "owner: adds owned repository ids" do
          repo_a = create(:public_repository, owner: @org)
          repo_b = create(:private_repository, owner: @org)
          repo_c = create(:private_repository, owner: @org)

          act_as(@searcher)
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "owner:#{@org.login}", current_user: @searcher)

          expected_query = {
            bool: {
              must: {
                terms: { repo_id: [repo_a.id, repo_b.id, repo_c.id] },
              }
            }
          }

          assert_equal expected_query, query.build_query
        end

        test "owner: adds only repository ids that the searcher has access to" do
          not_part_of_the_org_user = create(:user)
          repo_a = create(:public_repository, owner: @org)
          repo_b = create(:private_repository, owner: @org)
          repo_c = create(:private_repository, owner: @org)

          query = Search::Queries::ConditionalIssueQuery.new(phrase: "owner:#{@org.login}", current_user: not_part_of_the_org_user)

          expected_query = {
            bool: {
              must: {
                term: { repo_id: repo_a.id },
              }
            }
          }

          assert_equal expected_query, query.build_query
        end

        test "owner: can be used multiple times" do
          repo_a = create(:public_repository, owner: @org)
          repo_b = create(:private_repository, owner: @org)
          repo_c = create(:private_repository, owner: @org)
          user_repo = create(:private_repository, owner: @searcher)

          act_as(@searcher)
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "owner:#{@org.login} OR owner:#{@searcher.login}", current_user: @searcher)

          expected_query = {
            bool: {
              must: {
                terms: { repo_id: [repo_a.id, repo_b.id, repo_c.id, user_repo.id] },
              }
            }
          }

          assert_equal expected_query, query.build_query
        end
      end

      test "queued" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:queued", current_user: @searcher)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: { term: { queued: true } },
                }
              },
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      context "public" do
        test "is:public" do
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:public", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: { term: { public: true } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "is:private" do
          repo = create(:private_repository, owner: @searcher)
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:private", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                {
                  bool: {
                    should: [
                      { term: { public: true } },
                      { term: { repo_id: repo.id } },
                    ]
                  }
                },
                {
                  bool: {
                    must: { term: { public: false } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end
      end

      context "reviewable-state" do
        test "is:draft with feature flag enabled" do
          enable_feature_flag(:reviewable_state_searching)
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:draft", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: { term: { reviewable_state: "draft" } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "reviewable-state draft" do
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "reviewable-state:draft", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: { term: { reviewable_state: "draft" } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end
      end

      context "draft" do
        test "is:draft with feature flag disabled" do
          disable_feature_flag(:reviewable_state_searching)
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:draft", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: { term: { draft: true } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "draft true" do
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "draft:true", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: { term: { draft: true } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "draft false" do
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "draft:false", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: { term: { draft: false } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end
      end

      context "archived" do
        test "archived true" do
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "archived:true", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: { term: { archived: true } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "archived false" do
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "archived:false", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: { term: { archived: false } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end
      end

      context "parent-issue" do
        test "parent-issue" do
          repo = create(:repository, owner: @org)
          issue = create(:issue, repository: repo)
          parent = "#{repo.name_with_display_owner}##{issue.number}"
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "parent-issue:#{parent}", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: { term: { parent_issue: parent } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "no:parent-issue" do
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "no:parent-issue", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: {
                      bool: {
                        must_not: {
                          exists: { field: :parent_issue }
                        }
                      }
                    }
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "-parent-issue" do
          repo = create(:repository, owner: @org)
          issue = create(:issue, repository: repo)
          parent = "#{repo.name_with_display_owner}##{issue.number}"
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "-parent-issue:#{parent}", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must_not: { term: { parent_issue: parent } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end
      end

      context "sub-issue" do
        test "sub-issue" do
          repo = create(:repository, owner: @org)
          issue = create(:issue, repository: repo)
          sub_issue = "#{repo.name_with_display_owner}##{issue.number}"
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "sub-issue:#{sub_issue}", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: { term: { sub_issue: sub_issue } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "no:sub-issue" do
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "no:sub-issue", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must: {
                      bool: {
                        must_not: {
                          exists: { field: :sub_issue }
                        }
                      }
                    }
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end

        test "-sub-issue" do
          repo = create(:repository, owner: @org)
          issue = create(:issue, repository: repo)
          sub_issue = "#{repo.name_with_display_owner}##{issue.number}"
          query = Search::Queries::ConditionalIssueQuery.new(phrase: "-sub-issue:#{sub_issue}", current_user: @searcher)

          expected_query = {
            bool: {
              must: [
                { term: { public: true } },
                {
                  bool: {
                    must_not: { term: { sub_issue: sub_issue } },
                  }
                },
              ]
            }
          }

          assert_equal expected_query, query.build_query_filter
        end
      end
    end

    context "project" do
      test "generates a project filter for a repository-owned project" do
        project = create(:project)
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "project:#{project.owner.name_with_owner}/#{project.number}", current_user: @searcher)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: { term: { project_ids: project.id } },
                }
              },
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "generates a project filter for an organization-owned project" do
        org = create(:organization)
        project = create(:project, owner: org)
        org.add_member(@searcher)
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "project:#{org.login}/#{project.number}", current_user: @searcher)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: { term: { project_ids: project.id } },
                }
              },
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "generates a project filter for an organization-owned memex project" do
        org = create(:organization)
        memex = create(:memex_project, owner: org)
        org.add_member(@searcher)

        query = Search::Queries::ConditionalIssueQuery.new(phrase: "project:#{org.login}/#{memex.number}", current_user: @searcher)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: { term: { memex_project_ids: memex.id } },
                }
              },
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "generates a project filter for an organization-owned project + memex project" do
        org = create(:organization)
        project = create(:project, owner: org)
        memex = create(:memex_project, owner: org)
        org.add_member(@searcher)

        query = Search::Queries::ConditionalIssueQuery.new(phrase: "project:#{org.login}/#{project.number} project:#{org.login}/#{memex.number}", current_user: @searcher)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: {
                    bool: {
                      must: [
                        { term: { project_ids: project.id } },
                        { term: { memex_project_ids: memex.id } },
                      ]
                    }
                  }
                }
              },
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "generates an invalid filter for an inaccessible project" do
        private_repo = create(:private_repository)
        project = create(:project, owner: private_repo)

        query = Search::Queries::ConditionalIssueQuery.new(phrase: "project:#{private_repo.name_with_owner}/#{project.number}", current_user: @searcher)
        expected_query = {
          bool: {
            must: {
              term: { public: true }
            }
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "generates an invalid filter for an inaccessible memex project" do
        org = create(:organization)
        memex = create(:memex_project, owner: org)

        query = Search::Queries::ConditionalIssueQuery.new(phrase: "project:#{org.login}/#{memex.number}", current_user: @searcher)
        expected_query = {
          bool: {
            must: {
              term: { public: true }
            }
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "generates a project exclusion filter" do
        project = create(:project)
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "-project:#{project.owner.name_with_owner}/#{project.number}", current_user: @searcher)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must_not: { term: { project_ids: project.id } },
                }
              },
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "generates a project exclusion filter for memex project" do
        org = create(:organization)
        memex = create(:memex_project, owner: org)
        org.add_member(@searcher)

        query = Search::Queries::ConditionalIssueQuery.new(phrase: "-project:#{org.login}/#{memex.number}", current_user: @searcher)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must_not: { term: { memex_project_ids: memex.id } },
                }
              },
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "handles an OR between two project filters" do
        project = create(:project, owner: @searcher)

        org = create(:organization)
        org_project = create(:project, owner: org)
        org.add_member(@searcher)

        query = Search::Queries::ConditionalIssueQuery.new(phrase: "project:#{project.owner.name_with_owner}/#{project.number} OR project:#{org_project.owner.name_with_owner}/#{org_project.number}", current_user: @searcher)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  should: { terms: { project_ids: [project.id, org_project.id] } },
                  minimum_should_match: 1,
                }
              },
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "handles an OR between two memex filters" do
        org = create(:organization)
        org.add_member(@searcher)
        memex_project_1 = create(:memex_project, owner: org)
        memex_project_2 = create(:memex_project, owner: org)

        query = Search::Queries::ConditionalIssueQuery.new(phrase: "project:#{memex_project_1.owner.name_with_owner}/#{memex_project_1.number} OR project:#{memex_project_2.owner.name_with_owner}/#{memex_project_2.number}", current_user: @searcher)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  should: { terms: { memex_project_ids: [memex_project_1.id, memex_project_2.id] } },
                  minimum_should_match: 1,
                }
              },
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "handles an OR between a project and a memex filter" do
        org = create(:organization)
        project = create(:project, owner: org)
        memex = create(:memex_project, owner: org)
        org.add_member(@searcher)

        query = Search::Queries::ConditionalIssueQuery.new(phrase: "project:#{org.login}/#{project.number} OR project:#{org.login}/#{memex.number}", current_user: @searcher)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  should: [
                    { term: { project_ids: project.id } },
                    { term: { memex_project_ids: memex.id } },
                  ],
                  minimum_should_match: 1,
                }
              },
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "does not include a project in the search query if it is inaccessible" do
        private_repo = create(:private_repository)
        private_project = create(:project, owner: private_repo)
        project = create(:project, owner: @searcher)
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "project:#{private_repo.name_with_owner}/#{private_project.number} OR project:#{project.owner.name_with_owner}/#{project.number}", current_user: @searcher)
        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  should: { term: { project_ids: project.id } },
                  minimum_should_match: 1,
                }
              },
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter

      end
    end

    context "reason" do
      test "reason:not-planned" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "reason:not-planned", current_user: @searcher)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              { bool:
                {
                  must: {
                    term: {
                      state_reason: "not_planned"
                    }
                  }
                }
              }
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "reason:completed" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "reason:completed", current_user: @searcher)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: {
                    bool: {
                      must: { term: { state: "closed" } },
                      must_not: { exists: { field: "state_reason" } }
                    }
                  }
                }
              }
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "multiple reasons can be AND'ed implicitly" do
        query = Search::Queries::ConditionalIssueQuery.new(
          phrase: "reason:not-planned reason:completed",
          current_user: @searcher
        )

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: [
                    { term: { state_reason: "not_planned" } },
                    {
                      bool: {
                        must: { term: { state: "closed" } },
                        must_not: { exists: { field: "state_reason" } }
                      }
                    }
                  ]
                }
              }
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "multiple reasons can be AND'ed explicitly" do
        query = Search::Queries::ConditionalIssueQuery.new(
          phrase: "reason:completed AND reason:not-planned ",
          current_user: @searcher)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: [
                    {
                      bool: {
                        must: { term: { state: "closed" } },
                        must_not: { exists: { field: "state_reason" } }
                      }
                    },
                    { term: { state_reason: "not_planned" } }
                  ]
                }
              }
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "multiple reasons can be OR'ed" do
        query = Search::Queries::ConditionalIssueQuery.new(
          phrase: "reason:completed OR reason:not-planned ",
          current_user: @searcher)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  should: [
                    {
                      bool: {
                        must: { term: { state: "closed" } },
                        must_not: { exists: { field: "state_reason" } }
                      }
                    },
                    { term: { state_reason: "not_planned" } }
                  ],
                  minimum_should_match: 1
                }
              }
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "multiple negated reasons can be AND'ed" do
        query = Search::Queries::ConditionalIssueQuery.new(
          phrase: "-reason:completed AND -reason:not-planned ",
          current_user: @searcher
        )
        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: [
                    {
                      bool: {
                        should: [
                          { exists: { field: "state_reason" } },
                          { term: { state: "open" } },
                        ]
                      }
                    },
                    { bool: { must_not: { term: { state_reason: "not_planned" } } } }
                  ]
                }
              }
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "multiple negated reasons can be OR'ed" do
        query = Search::Queries::ConditionalIssueQuery.new(
          phrase: "-reason:completed OR -reason:not-planned ",
          current_user: @searcher
        )
        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  should: [
                    {
                      bool: {
                        should: [
                          { exists: { field: "state_reason" } },
                          { term: { state: "open" } },
                        ]
                      }
                    },
                    { bool: { must_not: { term: { state_reason: "not_planned" } } } }
                  ],
                  minimum_should_match: 1
                }
              }
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "multiple reasons expression" do
        query = Search::Queries::ConditionalIssueQuery.new(
          phrase: "reason:completed OR -reason:not-planned AND reason:not_planned",
          current_user: @searcher
        )
        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  should: [ # OR
                    { # reason:completed
                      bool: {
                        should: {
                          bool: {
                            must: { term: { state: "closed" } },
                            must_not: { exists: { field: "state_reason" } },
                          },
                        },
                        minimum_should_match: 1,
                      },
                    }, {
                      bool: {
                        must: [ # AND
                          # reason:not_planned
                          { term: { state_reason: "not_planned" } },
                          # -reason:not_planned
                          { bool: { must_not: { term: { state_reason: "not_planned" } } } },
                        ],
                      },
                    },
                  ],
                },
              },
            ],
          },
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "AND query with reason filter" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "reason:completed AND author:#{@monalisa.login}", current_user: @searcher)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: [
                    {
                      term: { author_id: @monalisa.id }
                    },
                    {
                      bool: {
                        must: { term: { state: "closed" } },
                        must_not: { exists: { field: "state_reason" } }
                      },
                    },
                  ]
                }
              }
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "OR query with reason filter" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "reason:not-planned OR author:#{@monalisa.login}", current_user: @searcher)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  should: [
                    {
                      term: { author_id: @monalisa.id }
                    },
                    {
                      term: { state_reason: "not_planned" }
                    },
                  ],
                  minimum_should_match: 1,
                }
              }
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "nested query with reason filters" do
        query = Search::Queries::ConditionalIssueQuery.new(
          phrase: "(reason:not-planned AND author:#{@monalisa.login}) OR (reason:completed AND author:#{@searcher.login})",
          current_user: @searcher
        )

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  should: [
                    {
                      bool: {
                        must: [
                          {
                            term: { author_id: @monalisa.id }
                          },
                          {
                            term: { state_reason: "not_planned" }
                          }
                        ]
                      }
                    },
                    {
                      bool: {
                        must: [
                          {
                            term: { author_id: @searcher.id }
                          },
                          {
                            bool: {
                              must: { term: { state: "closed" } },
                              must_not: { exists: { field: "state_reason" } }
                            }
                          },
                        ]
                      }
                    },
                  ]
                }
              }
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end
    end

    context "invalid fields" do
      test "Does not map an invalid field in a nested query, reduces the query to a single term" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "label:bug OR color:red")
        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: { term: { labels: "bug" } },
                }
              },
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "Builds an empty query for a nested query in which all terms are invalid" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "shape:circle OR color:red")
        expected_query = {
          bool: {
            must: { term: { public: true } },
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "Does not map invalid terms in a deeply nested query" do
        # label:enhancement OR ((state:closed OR shape:circle) AND (animal:cat OR color:red))
        # After stripping the invalid terms: label:enhancement OR ((state:closed OR -))
        # Since there is an OR with a single term: label:enhancement OR (state:closed)
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "label:enhancement OR ((archived:true OR shape:circle) AND (animal:cat OR color:red))")

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  should: [
                    { terms: { labels: ["enhancement"] } },
                    { term: { archived: true } },
                  ],
                  minimum_should_match: 1,
                }
              },
            ]
          }
        }
        assert_equal expected_query, query.build_query_filter
      end
    end
  end

  context "#index" do
    context "App installations" do
      test "permissions for issues only" do
        installation = make_integration_installation(repository: create(:private_repository), permissions: { "issues" => :read })

        allowed = Search::Queries::ConditionalIssueQuery.new(phrase: "is:issue AND is:open AND is:public", current_user: installation.bot)
        allowed.query_params
        assert_equal @issues_index, allowed.index.name

        not_allowed = Search::Queries::ConditionalIssueQuery.new(phrase: "(is:issue OR is:pr) AND is:open AND is:public", current_user: installation.bot)
        not_allowed.query_params
        assert_equal @issues_index, not_allowed.index.name
      end

      test "permissions for pull-requests only" do
        installation = make_integration_installation(repository: create(:private_repository), permissions: { "pull_requests" => :read })

        not_allowed = Search::Queries::ConditionalIssueQuery.new(phrase: "(is:issue OR is:pr) AND is:open AND is:public", current_user: installation.bot)
        not_allowed.query_params
        assert_equal @prs_index, not_allowed.index.name

        allowed = Search::Queries::ConditionalIssueQuery.new(phrase: "is:pr AND is:open AND is:public", current_user: installation.bot)
        allowed.query_params
        assert_equal @prs_index, allowed.index.name
      end

      test "permissions for issues and pull-requests" do
        installation = make_integration_installation(repository: create(:private_repository), permissions: { "issues" => :read, "pull_requests" => :read })

        allowed = Search::Queries::ConditionalIssueQuery.new(phrase: "(is:issue OR is:pr) AND is:open AND is:public", current_user: installation.bot)
        allowed.query_params
        assert_equal @default_index, allowed.index.name
      end
    end

    test "issues index type" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:issue AND is:open AND is:public")
      query.query_params
      assert_equal @issues_index, query.index.name
    end

    test "prs index type" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:open AND is:pr AND is:public")
      query.query_params
      assert_equal @prs_index, query.index.name
    end

    test "issues and prs index type" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:pr OR is:issue AND is:open")
      query.query_params
      assert_equal @default_index, query.index.name
    end

    test "default index type" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "")
      query.query_params
      assert_equal @default_index, query.index.name
    end

    test "default index type when wrong qualifier is entered" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:cat AND state:open")
      query.query_params
      assert_equal @default_index, query.index.name
    end

    test "prs index type when type:pr is entered" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "type:pr AND is:open")
      query.query_params
      assert_equal @prs_index, query.index.name
    end

    test "default index for type issues and prs" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "type:pr OR type:issue AND is:open")
      query.query_params
      assert_equal @default_index, query.index.name
    end

    test "issues index for multiple issue types" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "type:Epic,Bug AND is:open AND is:public")
      query.query_params
      assert_equal @issues_index, query.index.name
    end

    test "sets index to Issues if linked:pr and :type nil" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "linked:pr label:a")
      query.query_params
      assert_equal @issues_index, query.index.name
    end

    test "sets index to PullRequests if linked:issue and :type nil" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "linked:issue label:a")
      query.query_params
      assert_equal @prs_index, query.index.name
    end

    test "sets index to nil if linked:issue and linked:pr and :type nil" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "linked:issue AND linked:pr label:a")
      query.query_params
      assert_equal @default_index, query.index.name
    end

    test "Uses the default index if linked:issue and :type not nil" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "type:issue linked:issue label:a")
      query.query_params
      assert_equal @default_index, query.index.name
    end
  end

  context "when determining whether to use a candidate repo search" do
    context "#use_candidate_repo_search?" do
      test "returns true if a current user is present and we use a flagged search qualifier" do
        qualifier = Search::Queries::IssueQuery::CANDIDATE_REPO_SEARCH_QUALIFIERS.first
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "#{qualifier}:#{@searcher.login}", current_user: @searcher)
        assert_predicate query, :use_candidate_repo_search?
      end

      test "returns true if team filter is used" do
        qualifier = :team
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "#{qualifier}:#{@searcher.login}", current_user: @searcher)
        assert_predicate query, :use_candidate_repo_search?
      end

      test "returns false if a repo_id is present" do
        repo = create(:repository, name: "grit", owner: @searcher)
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "author:#{@searcher.login}", repo_id: repo.id, current_user: @searcher)
        refute_predicate query, :use_candidate_repo_search?
      end

      test "returns false if there is no current_user" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "search")
        refute_predicate query, :use_candidate_repo_search?
      end

      test "returns false if we scope to repos owned by a user" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "author:#{@searcher.login} user:#{@searcher.login}", current_user: @searcher)
        refute_predicate query, :use_candidate_repo_search?
      end

      test "returns false if we scope to repos owned by a user with owner:" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "author:#{@searcher.login} owner:#{@searcher.login}", current_user: @searcher)
        refute_predicate query, :use_candidate_repo_search?
      end

      test "returns false if we scope to repos owned by an org" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "author:#{@searcher.login} org:#{@org.name}", current_user: @searcher)
        refute_predicate query, :use_candidate_repo_search?
      end

      test "returns false if we scope to public repos" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "author:#{@searcher.login} is:public", current_user: @searcher)
        refute_predicate query, :use_candidate_repo_search?
      end
    end
  end

  context "enumerable values" do
    context "label" do
      test "enumerable terms for label with implicit AND" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "label:Bug,Enterprise archived:true", current_user: @searcher)
        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: { term: { archived: true } },
                  should: { terms: { labels: %w[bug enterprise] } },
                  minimum_should_match: 1,
                }
              },
            ]
          }
        }
        assert_equal expected_query, query.build_query_filter
      end

      test "enumerable terms for label with explicit AND" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "label:Bug,Enterprise AND archived:true", current_user: @searcher)
        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: { term: { archived: true } },
                  should: { terms: { labels: %w[bug enterprise] } },
                  minimum_should_match: 1,
                }
              },
            ]
          }
        }
        assert_equal expected_query, query.build_query_filter
      end

      test "enumerable terms for label with OR" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "label:Bug,Enterprise OR archived:true", current_user: @searcher)
        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  should: [
                    { terms: { labels: %w[bug enterprise] } },
                    { term: { archived: true } },
                  ],
                  minimum_should_match: 1,
                }
              },
            ]
          }
        }
        assert_equal expected_query, query.build_query_filter
      end

      test "enumerable terms for negative labels generate must_not query" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "-label:bug,docs", current_user: @searcher)
        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must_not: [
                    { term: { labels: "bug" } },
                    { term: { labels: "docs" } },
                  ]
                }
              },
            ]
          }
        }
        assert_equal expected_query, query.build_query_filter
      end

      test "enumerable terms for negative label with explicit AND generates must_not query" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "-label:bug AND -label:docs", current_user: @searcher)
        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must_not: [
                    { term: { labels: "bug" } },
                    { term: { labels: "docs" } },
                  ]
                }
              },
            ]
          }
        }
        assert_equal expected_query, query.build_query_filter
      end

      test "enumerable terms for negative label with OR aggregates must_not with should query" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "label:bug,fix OR -label:docs,adr", current_user: @searcher)
        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  should: [
                    {
                      bool: {
                        should: { terms: { labels: %w(bug fix) } },
                        minimum_should_match: 1,
                      },
                    },
                    {
                      bool: {
                        must_not: {
                          bool: {
                            must: [
                              { term: { labels: "docs" } },
                              { term: { labels: "adr" } },
                            ]
                          }
                        }
                      },
                    },
                  ],
                },
              },
            ],
          }
        }
        assert_equal expected_query, query.build_query_filter
      end

      test "enumerable terms for no filter OR'd with positive filter" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "label:bug,fix OR no:label", current_user: @searcher)
        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  should: [
                    {
                      bool: {
                        should: { terms: { labels: %w(bug fix) } },
                        minimum_should_match: 1,
                      },
                    },
                    {
                      bool: {
                        must: {
                          bool: {
                            must_not: { exists: { field: :labels } }
                          }
                        },
                      },
                    },
                  ],
                },
              },
            ],
          }
        }
        assert_equal expected_query, query.build_query_filter
      end
    end

    context "type" do
      test "enumerable terms for type with implicit AND" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "type:Task,Epic label:one")

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: { term: { labels: "one" } },
                  should: { terms: { issue_type_name: %w(epic task) } },
                  minimum_should_match: 1,
                }
              }
            ]
          }
        }
        assert_equal expected_query, query.build_query_filter
      end

      test "enumerable terms for type with explicit AND" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "type:Task,Epic AND label:one")

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: { term: { labels: "one" } },
                  should: { terms: { issue_type_name: %w(epic task) } },
                  minimum_should_match: 1,
                }
              }
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "enumerable terms for type with OR" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "type:Task,Epic OR label:one")

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  should: [
                    { terms: { labels: ["one"] } },
                    { terms: { issue_type_name: %w(epic task) } }
                  ],
                  minimum_should_match: 1,
                }
              }
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "no:type" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "no:type", current_user: @searcher)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: {
                    bool: {
                      must_not: {
                        exists: { field: :issue_type_name }
                      }
                    }
                  }
                }
              },
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end

      test "has:type" do
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "has:type", current_user: @searcher)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: {
                    exists: { field: :issue_type_name }
                  }
                }
              },
            ]
          }
        }

        assert_equal expected_query, query.build_query_filter
      end
    end

    context "parent issue" do
      test "enumerable terms for parent-issue" do
        parent1 = "github/github#1"
        parent2 = "github/github#2"
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "parent-issue:#{parent1},#{parent2}")

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  should: { terms: { parent_issue: [parent1, parent2] } },
                  minimum_should_match: 1,
                },
              },
            ],
          },
        }
        assert_equal expected_query, query.build_query_filter
      end

      test "implicit AND for parent-issue filter generates a must fragment" do
        parent1 = "github/github#1"
        parent2 = "github/github#2"
        search_query = "parent-issue:#{parent1} parent-issue:#{parent2}"
        query = Search::Queries::ConditionalIssueQuery.new(phrase: search_query)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: {
                    bool: {
                      must: [
                        { term: { parent_issue: parent1 } },
                        { term: { parent_issue: parent2 } },
                      ],
                    },
                  },
                },
              },
            ],
          },
        }
        assert_equal expected_query, query.build_query_filter
      end

      test "OR'd parent-issue filters are joined into a single array" do
        parent1 = "github/github#1"
        parent2 = "github/github#2"
        parent3 = "github/github#3"
        parent4 = "github/github#4"
        search_query = "(parent-issue:#{parent1},#{parent2} OR parent-issue:#{parent3}) OR parent-issue:#{parent4}"
        query = Search::Queries::ConditionalIssueQuery.new(phrase: search_query)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  should: {
                    terms: { parent_issue: [parent1, parent2, parent3, parent4] }
                  },
                  minimum_should_match: 1,
                },
              },
            ],
          },
        }
        assert_equal expected_query, query.build_query_filter
      end

      test "parent-issue filter OR'd with no: filter" do
        parent1 = "github/github#1"
        parent2 = "github/github#2"
        search_query = "parent-issue:#{parent1},#{parent2} OR  no:parent-issue"
        query = Search::Queries::ConditionalIssueQuery.new(phrase: search_query)

        #binding.b

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  should: [
                    {
                      bool: {
                        should: { terms: { parent_issue: [parent1, parent2] } },
                        minimum_should_match: 1,
                      },
                    },
                    {
                      bool: {
                        must: {
                          bool: {
                            must_not: { exists: { field: :parent_issue } }
                          }
                        },
                      },
                    },
                  ],
                },
              },
            ],
          }
        }
        assert_equal expected_query, query.build_query_filter
      end
    end

    context "sub-issue" do
      test "enumerable terms for sub-issue" do
        sub_issue1 = "github/github#1"
        sub_issue2 = "github/github#2"
        query = Search::Queries::ConditionalIssueQuery.new(phrase: "sub-issue:#{sub_issue1},#{sub_issue2}")

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  should: { terms: { sub_issue: [sub_issue1, sub_issue2] } },
                  minimum_should_match: 1,
                }
              }
            ]
          }
        }
        assert_equal expected_query, query.build_query_filter
      end

      test "implicit AND for sub-issue filter generates a must fragment" do
        sub_issue1 = "github/github#1"
        sub_issue2 = "github/github#2"
        search_query = "sub-issue:#{sub_issue1} sub-issue:#{sub_issue2}"
        query = Search::Queries::ConditionalIssueQuery.new(phrase: search_query)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  must: {
                    bool: {
                      must: [
                        { term: { sub_issue: sub_issue1 } },
                        { term: { sub_issue: sub_issue2 } },
                      ],
                    },
                  },
                },
              },
            ],
          },
        }
        assert_equal expected_query, query.build_query_filter
      end

      test "OR'd sub-issue filters are joined into a single array" do
        sub_issue1 = "github/github#1"
        sub_issue2 = "github/github#2"
        sub_issue3 = "github/github#3"
        sub_issue4 = "github/github#4"
        search_query = "(sub-issue:#{sub_issue1},#{sub_issue2} OR sub-issue:#{sub_issue3}) OR sub-issue:#{sub_issue4}"
        query = Search::Queries::ConditionalIssueQuery.new(phrase: search_query)

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  should: {
                    terms: { sub_issue: [sub_issue1, sub_issue2, sub_issue3, sub_issue4] }
                  },
                  minimum_should_match: 1,
                },
              },
            ],
          },
        }
        assert_equal expected_query, query.build_query_filter
      end

      test "sub-issue filter OR'd with no: filter" do
        sub_issue1 = "github/github#1"
        sub_issue2 = "github/github#2"
        search_query = "sub-issue:#{sub_issue1},#{sub_issue2} OR  no:sub-issue"
        query = Search::Queries::ConditionalIssueQuery.new(phrase: search_query)

        #binding.b

        expected_query = {
          bool: {
            must: [
              { term: { public: true } },
              {
                bool: {
                  should: [
                    {
                      bool: {
                        should: { terms: { sub_issue: [sub_issue1, sub_issue2] } },
                        minimum_should_match: 1,
                      },
                    },
                    {
                      bool: {
                        must: {
                          bool: {
                            must_not: { exists: { field: :sub_issue } }
                          }
                        },
                      },
                    },
                  ],
                },
              },
            ],
          }
        }
        assert_equal expected_query, query.build_query_filter
      end
    end
  end

  context "wildcardable filters" do
    test "generates an exists fragment for assignee:*" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "assignee:*")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: {
                  exists: { field: :assignee_id }
                }
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "generates an exists fragment for milestone:*" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "milestone:*")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: {
                  exists: { field: :milestone_num }
                }
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end
  end

  context "#type qualifier" do
    test "adds issue_type_name field when looking a task type" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "type:task label:one")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: [
                  { term: { labels: "one" } },
                  { term: { issue_type_name: "task" } }
                ]
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "does not add field issue_type_name when searching for pr" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "type:pr label:one")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: [
                  { term: { labels: "one" } },
                  { prefix: { _index: "pull-requests" } }
                ]
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "does not add field issue_type_name when searching for issues" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "type:issue label:one")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: [
                  { term: { labels: "one" } },
                  { prefix: { _index: "issues" } }
                ]
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "adds two issue_type_name fields when looking for multipe types with AND" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "type:task AND type:epic AND label:one")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: [
                  { term: { labels: "one" } },
                  {
                    bool: {
                      must: [
                        { term: { issue_type_name: "task" } },
                        { term: { issue_type_name: "epic" } }
                      ]
                    }
                  }
                ]
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "adds issue_type_name field array when looking for multiple issue types" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "type:issue AND type:task AND label:one")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            bool: {
              must: [
                { term: { labels: "one" } },
                { term: { issue_type_name: "task" } },
                { prefix: { _index: "issues" } }
              ]
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "negative qualifier type generates must_not query" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "-type:task,epic")

      expected_query = {
        bool: {
          must: [
              { term: { public: true } },
              {
                bool: {
                  must_not: [
                    { term: { issue_type_name: "task" } },
                    { term: { issue_type_name: "epic" } },
                  ]
                }
              }
            ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "negative qualifier type for issues removes the _index issues from query" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "-type:issue OR type:pr")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                should: { prefix: { _index: "pull-requests" } },
                minimum_should_match: 1
              },
            },
          ],
        },
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "complex query with negative qualifier for type" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "type:Task OR (type:Epic AND -type:bug)")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                should: [
                  {
                    bool: {
                      must: { term: { issue_type_name: "task" } }
                    }
                  },
                  {
                    bool: {
                      must: { term: { issue_type_name: "epic" } },
                      must_not: { term: { issue_type_name: "bug" } }
                    }
                  }
                ]
              }
            }
          ]
        }
      }


      assert_equal expected_query, query.build_query_filter
    end

    test "complex nested query for type" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "type:enhancement OR ((label:one AND type:improvement) OR (label:two AND type:bug))")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                should: [
                  {
                    bool: {
                      must: { term: { issue_type_name: "enhancement" } },
                    }
                  },
                  {
                    bool: {
                      must: [
                        { term: { labels: "one" } },
                        { term: { issue_type_name: "improvement" } }
                      ]
                    }
                  },
                  {
                    bool: {
                      must: [
                        { term: { labels: "two" } },
                        { term: { issue_type_name: "bug" } }
                      ]
                    }
                  }
                ]
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "simple OR query for type" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "type:Task OR type:Epic")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                should: { terms: { issue_type_name: %w(task epic) } },
                minimum_should_match: 1,
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "pull-request OR issues for type" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "type:pull-request OR type:issues")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                should: {
                  bool: {
                    should: [
                      { prefix: { _index: "pull-requests" } },
                      { prefix: { _index: "issues" } }
                    ]
                  }
                },
                minimum_should_match: 1,
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end
  end

  context "head ref and base ref" do
    test "generates a base ref filter" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "base:main")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: { prefix: { base_ref: "main" } }
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "generates a base ref filter with special characters" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "base:branch/fixes-bug-🐛")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: { prefix: { base_ref: "branch/fixes-bug-🐛" } }
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "generates a negated base ref filter" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "-base:main")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must_not: { prefix: { base_ref: "main" } }
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "generates a head ref filter" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "head:topic")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: { prefix: { head_ref: "topic" } }
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "generates a head ref filter with special characters" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "head:branch/fixes-bug-🐛")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: { prefix: { head_ref: "branch/fixes-bug-🐛" } }
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "generates a negated head ref filter" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "-head:topic")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must_not: { prefix: { head_ref: "topic" } }
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "generates a combined head ref and base ref filter" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "head:topic base:main")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: [
                  { prefix: { head_ref: "topic" } },
                  { prefix: { base_ref: "main" } }
                ]
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "generates a mixed combined head ref and base ref filter" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "-head:topic base:main base:enterprise-release")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: {
                  bool: {
                    should: [
                      { prefix: { base_ref: "main" } },
                      { prefix: { base_ref: "enterprise-release" } }
                    ],
                  },
                },
                must_not: { prefix: { head_ref: "topic" } },
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end
  end

  context "date range filters" do
    test "generates a created filter" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "created:>2013-02-01")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: {
                  range: {
                    created_at: { gt: "2013-02-01||/d" }
                   }
                }
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "generates an updated filter" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "updated:<2013-02-01")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: {
                  range: {
                    updated_at: { lt: "2013-02-01||/d" }
                   }
                }
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "generates a closed filter" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "closed:>2013-02-01")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: {
                  range: {
                    closed_at: { gt: "2013-02-01||/d" }
                   }
                }
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "generates a merged filter" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "merged:>2013-02-01")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: {
                  range: {
                    merged_at: { gt: "2013-02-01||/d" }
                   }
                }
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "generates a filter with greater than or equal to" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "merged:>=2013-02-01")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: {
                  range: {
                    merged_at: { gte: "2013-02-01||/d" }
                   }
                }
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "generates a filter with less than or equal to" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "merged:<=2013-02-01")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: {
                  range: {
                    merged_at: { lte: "2013-02-01||/d" }
                   }
                }
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "generates a range filter" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "created:2013-02-01..2013-02-28")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: {
                  range: {
                    created_at: { gte: "2013-02-01||/d", lte: "2013-02-28||/d" }
                   }
                }
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end
  end

  context "range filters" do
    test "generates a number of comments filter" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "comments:>42")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: {
                  range: {
                    num_comments: { gt: "42" }
                   }
                }
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "generates a number of reactions filter" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "reactions:>42")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: {
                  range: {
                    num_reactions: { gt: "42" }
                   }
                }
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "generates a number of interactions filter" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "interactions:>42")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: {
                  range: {
                    num_interactions: { gt: "42" }
                   }
                }
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "linked:pr" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "linked:pr")
      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            { bool: { must: { term: { has_closing_reference: true } } } }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "linked:issue" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "linked:issue")
      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            { bool: { must: { term: { has_closing_reference: true } } } }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "linked:issue OR type:issue" do
      # All PRs that are "linked" + all issues
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "linked:issue OR type:issue")
      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                should: [
                  { prefix: { _index: "issues" } },
                  { term: { has_closing_reference: true } }
                ],
                minimum_should_match: 1,
              }
            }
          ]
        }
      }

      query.query_params
      assert_equal expected_query, query.build_query_filter
    end

    test "generates a bounded range filter" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "interactions:20..30")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: {
                  range: {
                    num_interactions: { gte: "20", lte: "30" }
                   }
                }
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "generates an OR query with range filters" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "interactions:>42 OR interactions:<=30")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                should: [
                  {
                    range: {
                      num_interactions: { gt: "42" }
                    }
                  },
                  {
                    range: {
                      num_interactions: { lte: "30" }
                    }
                  },
                ],
                minimum_should_match: 1,
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end

    test "generates an AND query with range filters" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "interactions:>42 AND interactions:<=30")

      expected_query = {
        bool: {
          must: [
            { term: { public: true } },
            {
              bool: {
                must: [
                  {
                    range: {
                      num_interactions: { gt: "42" }
                    }
                  },
                  {
                    range: {
                      num_interactions: { lte: "30" }
                    }
                  },
                ]
              }
            }
          ]
        }
      }

      assert_equal expected_query, query.build_query_filter
    end
  end

  context "#valid_query?" do
    test "returns true for a query with no specified ownership filters" do
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:issue state:open label:bug", current_user: @searcher)
      assert_predicate query, :valid_query?
    end

    test "returns false if filtering by a repo the user doesn't have access to" do
      repo = create(:private_repository)
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:issue state:open label:bug repo:#{repo.name_with_display_owner}", current_user: @searcher)
      refute_predicate query, :valid_query?
    end

    test "returns true if filtering by a repo the user does have access to" do
      repo = create(:private_repository, owner: @searcher)
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:issue state:open label:bug repo:#{repo.name_with_display_owner}", current_user: @searcher)
      assert_predicate query, :valid_query?
    end

    test "returns false if filtering by an owner the user doesn't have access to" do
      repo = create(:private_repository)
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:issue state:open label:bug owner:#{repo.owner.display_login}", current_user: @searcher)
      refute_predicate query, :valid_query?
    end

    test "returns true if filtering by an owner the user does have access to" do
      repo = create(:repository)
      act_as(@searcher)
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:issue state:open label:bug owner:#{repo.owner.display_login}", current_user: @searcher)
      assert_predicate query, :valid_query?
    end

    test "returns true if filtering by an themselves as owner" do
      repo = create(:private_repository, owner: @searcher)
      act_as(@searcher)
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:issue state:open label:bug owner:#{@searcher.display_login}", current_user: @searcher)
      assert_predicate query, :valid_query?
    end

    test "returns false if filtering by a user the user doesn't have access to" do
      repo = create(:private_repository)
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:issue state:open label:bug user:#{repo.owner.display_login}", current_user: @searcher)
      refute_predicate query, :valid_query?
    end

    test "returns true if filtering by a user the user does have access to" do
      repo = create(:repository)
      act_as(@searcher)
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:issue state:open label:bug user:#{repo.owner.display_login}", current_user: @searcher)
      assert_predicate query, :valid_query?
    end

    test "returns true if filtering by an themselves as user" do
      repo = create(:private_repository, owner: @searcher)
      act_as(@searcher)
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:issue state:open label:bug user:#{@searcher.display_login}", current_user: @searcher)
      assert_predicate query, :valid_query?
    end

    test "returns false if filtering by an org the user doesn't have access to" do
      org = create(:organization)
      repo = create(:private_repository, owner: org)
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:issue state:open label:bug org:#{org.display_login}", current_user: @searcher)

      refute_predicate query, :valid_query?
    end

    test "returns false if filtering by an org the user does have access to" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      act_as(@searcher)
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:issue state:open label:bug org:#{org.display_login}", current_user: @searcher)

      assert_predicate query, :valid_query?
    end

    test "returns true if filtering by an org the user is a member of" do
      org = create(:organization)
      org.add_member(@searcher)
      repo = create(:private_repository, owner: org)
      act_as(@searcher)
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:issue state:open label:bug org:#{org.display_login}", current_user: @searcher)

      assert_predicate query, :valid_query?
    end

    test "returns false if a filter is invalid" do
      # "involves" is a UserFilter and considers itself invalid if any of the logins can't be mapped to an ID
      # See ::Search::Filters::UserFilter#map_bool_collection
      query = Search::Queries::ConditionalIssueQuery.new(phrase: "is:issue state:open label:bug involves:not_a_user", current_user: @searcher)

      refute_predicate query, :valid_query?
    end

    context "#query limit" do
      test "returns true if query depth limit is equal or below QUERY_DEPTH_LIMIT" do
        query_depth_4 = "( is:issue AND state:open AND ( (author:@me OR author:collaborator) OR (assignee:@me OR assignee:collaborator) AND label:bug ) )"
        query = Search::Queries::ConditionalIssueQuery.new(phrase: query_depth_4, current_user: @searcher)

        assert_predicate query, :valid_query?
      end

      test "returns false if query depth limit is above QUERY_DEPTH_LIMIT" do
        query_depth_5 = "( is:issue AND state:open AND ( (author:@me OR author:collaborator) OR (assignee:@me OR assignee:collaborator) AND label:bug,epic) ) OR ( is:pr AND state:closed AND linked:issue )"
        query = Search::Queries::ConditionalIssueQuery.new(phrase: query_depth_5, current_user: @searcher)

        refute_predicate query, :valid_query?
      end
    end
  end
end
