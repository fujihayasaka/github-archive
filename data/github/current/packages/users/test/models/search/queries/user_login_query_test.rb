# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesUserLoginQueryTest < GitHub::TestCase
  fixtures do
    @rails    = create(:user, login: "rails")
    @railyard = create(:user, login: "railyard")
    @raid     = create(:user, login: "raid")
    @giants   = create(:user, login: "giants")
    @rails.profile    = create(:profile, name: "First Last")
    @railyard.profile = create(:profile, name: "First Second")
    @raid.profile     = create(:profile, name: "Route")
    @giants.profile   = create(:profile, name: "Route Giants")
    @friends = [@rails, @railyard, @raid]

    @chip = create(:user, login: "chip")
    @chipmunk = create(:user, login: "chipmunk")
    @chipmunks = create(:user, login: "chipmunks")

    @org = create :organization, login: "the-forest"
    @org.add_member(@chipmunk)
    @org.publicize_member(@chipmunk)
    @org.add_member(@chipmunks)

    unless GitHub.single_business_environment?
      @emu_user = create(:emu, :owner, login: "testuser-emu")
      @emu_enterprise = @emu_user.enterprise_managed_business
      @emu_user_suspended = create(:emu, business: @emu_enterprise, login: "testuser-emu-suspended")
      @emu_user_suspended.update(suspended_at: Time.now)
      @emu_organization = create(:enterprise_linked_organization,
                                  business: @emu_enterprise,
                                  login: "testorg-emu",
                                  admin: @emu_user)

      @emu_user_2 = create(:emu, :owner, login: "testuser-emu-2")
      @emu_enterprise_2 = @emu_user_2.enterprise_managed_business
      @emu_organization_2 = create(:enterprise_linked_organization,
                                    business: @emu_enterprise_2,
                                    login: "testorg-emu-2",
                                    admin: @emu_user_2)

      @non_emu_enterprise = create(:business)
      @non_emu_user = create(:user, login: "testuser-non-emu")
      @non_emu_enterprise.add_user_accounts([@non_emu_user.id])
      @non_emu_organization = create(:organization, login: "testorg-non-emu")
      @non_emu_enterprise.add_organization(@non_emu_organization)
    end
  end

  setup do
    setup_search
    make_searchable(@rails, @railyard, @raid, @giants, @chip, @chipmunk, @chipmunks)
  end

  teardown { teardown_search }


  context "when building the query" do
    test "defaults" do
      query = Search::Queries::UserLoginQuery.new
      assert_equal({ constant_score: { filter: { bool: { must_not: { exists: { field: :business_id } } } } } }, query.build_query)
    end

    test "it creates a string query" do
      query = Search::Queries::UserLoginQuery.new(phrase: "drewb")
      expected_query = {
        bool: {
          must: {
            multi_match: {
              query: "drewb",
              fields: ["login^10", "name", "login.ngram^0.8"],
              operator: "AND",
              type: "most_fields",
              analyzer: "lowercase",
            }
          },
          filter: {
            bool: {
              must_not: {
                exists: {
                  field: :business_id
                }
              }
            }
          }
        }
      }

      assert_equal expected_query, query.build_query
    end

    test "allows the exclusion of suspended users" do
      query = Search::Queries::UserLoginQuery.new(phrase: "drewb", exclude_suspended: true)
      expected_query = {
        bool: {
          must_not: {
              exists: {
                field: :suspended_at
              }
          },
          must: {
            multi_match: {
              query: "drewb",
              fields: ["login^10", "name", "login.ngram^0.8"],
              operator: "AND",
              type: "most_fields",
              analyzer: "lowercase",
            },
          },
          filter: {
            bool: {
              must_not: {
                exists: {
                  field: :business_id
                }
              }
            }
          }
        },
      }
      assert_equal expected_query, query.build_query
    end

    test "it creates a string query with friends present" do
      query = Search::Queries::UserLoginQuery.new(phrase: "drewb", friends: [@rails])
      expected_query = {
        bool: {
          must: {
            function_score: {
              query: {
                multi_match: {
                  query: "drewb",
                  fields: ["login^10", "name", "login.ngram^0.8"],
                  operator: "AND",
                  type: "most_fields",
                  analyzer: "lowercase",
                },
              },
              functions: [
                {
                  filter: {
                    terms: {
                      user_id: [@rails.id],
                    },
                  },
                  weight: 10,
                },
              ],
            },
          },
          filter: {
            bool: {
              must_not: {
                exists: {
                  field: :business_id
                }
              }
            }
          }
        }
      }

      assert_equal expected_query, query.build_query
    end

    test "it creates a string query with `public_org_ids` present when public viewer on the passed in org" do
      query = Search::Queries::UserLoginQuery.new(phrase: "drewb", org: @org)
      expected_query = {
        bool: {
          must: {
            function_score: {
              query: {
                multi_match: {
                  query: "drewb",
                  fields: ["login^10", "name", "login.ngram^0.8"],
                  operator: "AND",
                  type: "most_fields",
                  analyzer: "lowercase",
                },
              },
              functions: [
                {
                  filter: {
                    term: {
                      public_org_ids: @org.id,
                    },
                  },
                  weight: 10,
                },
              ],
            },
          },
          filter: {
            bool: {
              must_not: {
                exists: {
                  field: :business_id
                }
              }
            }
          }
        }
      }

      assert_equal expected_query, query.build_query
    end

    test "it creates a string query with `all_org_ids` present when viewer is a member of the passed in org" do
      query = Search::Queries::UserLoginQuery.new(phrase: "drewb", org: @org, current_user: @chipmunk)
      expected_query = {
        bool: {
          must: {
            function_score: {
              query: {
                multi_match: {
                  query: "drewb",
                  fields: ["login^10", "name", "login.ngram^0.8"],
                  operator: "AND",
                  type: "most_fields",
                  analyzer: "lowercase",
                },
              },
              functions: [
                {
                  filter: {
                    term: {
                      all_org_ids: @org.id,
                    },
                  },
                  weight: 10,
                },
              ],
            },
          },
          filter: {
            bool: {
              must_not: {
                exists: {
                  field: :business_id
                }
              }
            }
          }
        }
      }

      assert_equal expected_query, query.build_query
    end

    context "EMU context" do
      unless GitHub.single_business_environment?
        test "EMU business and @excluded_suspended is true" do
          query = Search::Queries::UserLoginQuery.new(phrase: "testuser-", business: @emu_enterprise, exclude_suspended: true)
          expected_query = {
            bool: {
              must_not: {
                exists: {
                  field: :suspended_at
                }
              },
              must: {
                multi_match: {
                  query: "testuser-",
                  fields: ["login^10", "name", "login.ngram^0.8"],
                  operator: "AND",
                  type: "most_fields",
                  analyzer: "lowercase"
                }
              },
              filter: {
                bool: {
                  must: {
                    term: {
                      business_id: @emu_enterprise.id
                    }
                  }
                }
              }
            }
          }

          assert_equal expected_query, query.build_query
        end

        test "EMU business and @excluded_suspended is false" do
          query = Search::Queries::UserLoginQuery.new(phrase: "testuser-", business: @emu_enterprise, exclude_suspended: false)
          expected_query = {
            bool: {
              must: {
                multi_match: {
                  query: "testuser-",
                  fields: ["login^10", "name", "login.ngram^0.8"],
                  operator: "AND",
                  type: "most_fields",
                  analyzer: "lowercase"
                }
              },
              filter: {
                bool: {
                  must: {
                    term: {
                      business_id: @emu_enterprise.id
                    }
                  }
                }
              }
            }
          }

          assert_equal expected_query, query.build_query
        end

        test "EMU org and @excluded_suspended is true" do
          query = Search::Queries::UserLoginQuery.new(phrase: "testuser-", org: @emu_organization, exclude_suspended: true)
          expected_query = {
            bool: {
              must_not: {
                exists: {
                  field: :suspended_at
                }
              },
              must: {
                function_score: {
                  query: {
                    multi_match: {
                      query: "testuser-",
                      fields: ["login^10", "name", "login.ngram^0.8"],
                      operator: "AND",
                      type: "most_fields",
                      analyzer: "lowercase"
                    }
                  },
                  functions: [
                    {
                      filter: {
                        term: {
                          public_org_ids: @emu_organization.id
                        }
                      },
                      weight: 10
                    }
                  ]
                }
              },
              filter: {
                bool: {
                  must: {
                    term: {
                      business_id: @emu_organization.business.id
                    }
                  }
                }
              }
            }
          }

          assert_equal expected_query, query.build_query
        end

        test "EMU org and @excluded_suspended is false" do
          query = Search::Queries::UserLoginQuery.new(phrase: "testuser-", org: @emu_organization, exclude_suspended: false)
          expected_query = {
            bool: {
              must: {
                function_score: {
                  query: {
                    multi_match: {
                      query: "testuser-",
                      fields: ["login^10", "name", "login.ngram^0.8"],
                      operator: "AND",
                      type: "most_fields",
                      analyzer: "lowercase"
                    }
                  },
                  functions: [
                    {
                      filter: {
                        term: {
                          public_org_ids: @emu_organization.id
                        }
                      },
                      weight: 10
                    }
                  ]
                }
              },
              filter: {
                bool: {
                  must: {
                    term: {
                      business_id: @emu_organization.business.id
                    }
                  }
                }
              }
            }
          }

          assert_equal expected_query, query.build_query
        end

        test "non EMU business" do
          query = Search::Queries::UserLoginQuery.new(phrase: "testuser-", business: @non_emu_enterprise)
          expected_query = {
            bool: {
              must: {
                multi_match: {
                  query: "testuser-",
                  fields: ["login^10", "name", "login.ngram^0.8"],
                  operator: "AND",
                  type: "most_fields",
                  analyzer: "lowercase"
                }
              },
              filter: {
                bool: {
                  must_not: {
                    exists: {
                      field: :business_id
                    }
                  }
                }
              }
            }
          }
          assert_equal expected_query, query.build_query
        end

        test "non EMU org" do
          query = Search::Queries::UserLoginQuery.new(phrase: "testuser-", org: @non_emu_organization)
          expected_query = {
            bool: {
              must: {
                function_score: {
                  query: {
                    multi_match: {
                      query: "testuser-",
                      fields: ["login^10", "name", "login.ngram^0.8"],
                      operator: "AND",
                      type: "most_fields",
                      analyzer: "lowercase"
                    }
                  },
                  functions: [
                    {
                      filter: {
                        term: {
                          public_org_ids: @non_emu_organization.id
                        }
                      },
                      weight: 10
                    }
                  ]
                }
              },
              filter: {
                bool: {
                  must_not: {
                    exists: {
                      field: :business_id
                    }
                  }
                }
              }
            }
          }
          assert_equal expected_query, query.build_query
        end
      end
    end
  end

  context "when querying" do
    context "org argument" do
      test "when no org value, no org member boosting" do
        query = Search::Queries::UserLoginQuery.new(phrase: "chi")
        results = query.execute.results.map { |h| h["_model"] }
        assert_equal [@chip, @chipmunk, @chipmunks], results
      end

      test "when org value supplied, boost publicized org members" do
        query = Search::Queries::UserLoginQuery.new(phrase: "chi", org: @org)
        results = query.execute.results.map { |h| h["_model"] }
        assert_equal [@chipmunk, @chip, @chipmunks], results
      end

      test "when org value supplied and viewer is a member, boost all org members" do
        query = Search::Queries::UserLoginQuery.new(phrase: "chi", org: @org, current_user: @chipmunk)
        results = query.execute.results.map { |h| h["_model"] }
        assert_equal [@chipmunk, @chipmunks, @chip], results
      end
    end

    context "with friends" do
      test "matches user login" do
        query = Search::Queries::UserLoginQuery.new(phrase: "rail", friends: @friends)
        results = query.execute.results.map { |h| h["_model"] }
        assert_equal [@rails, @railyard], results
      end

      test "matches user profile name" do
        query = Search::Queries::UserLoginQuery.new(phrase: "first", friends: @friends)
        results = query.execute.results.map { |h| h["_model"] }
        assert_equal [@rails, @railyard], results
      end

      test "boosts user profile name when matching" do
        query = Search::Queries::UserLoginQuery.new(phrase: "route", friends: @friends)
        results = query.execute.results.map { |h| h["_model"] }
        assert_equal [@raid, @giants], results
      end
    end

    context "EMU context" do
      unless GitHub.single_business_environment?
        test "EMU business and @excluded_suspended is true only returns non-suspended user and orgs in same EMU business" do
          make_searchable(@emu_user, @emu_user_2, @emu_user_suspended, @non_emu_user, @emu_organization, @emu_organization_2, @non_emu_organization)

          query = Search::Queries::UserLoginQuery.new(phrase: "test", business: @emu_enterprise, exclude_suspended: true)
          results = query.execute.results.map { |h| h["_model"] }
          assert_same_elements [@emu_user, @emu_organization], results
        end

        test "EMU business and @excluded_suspended is false only returns user and orgs in same EMU business" do
          make_searchable(@emu_user, @emu_user_2, @emu_user_suspended, @non_emu_user, @emu_organization, @emu_organization_2, @non_emu_organization)

          query = Search::Queries::UserLoginQuery.new(phrase: "test", business: @emu_enterprise, exclude_suspended: false)
          results = query.execute.results.map { |h| h["_model"] }
          assert_same_elements [@emu_user, @emu_user_suspended, @emu_organization], results
        end

        test "EMU org and @excluded_suspended is true only returns non-suspended user and orgs in same EMU business" do
          make_searchable(@emu_user, @emu_user_2, @emu_user_suspended, @non_emu_user, @emu_organization, @emu_organization_2, @non_emu_organization)

          query = Search::Queries::UserLoginQuery.new(phrase: "test", org: @emu_organization, exclude_suspended: true)
          results = query.execute.results.map { |h| h["_model"] }
          assert_same_elements [@emu_user, @emu_organization], results
        end

        test "EMU org and @excluded_suspended is false only returns user and orgs in same EMU business" do
          make_searchable(@emu_user, @emu_user_2, @emu_user_suspended, @non_emu_user, @emu_organization, @emu_organization_2, @non_emu_organization)

          query = Search::Queries::UserLoginQuery.new(phrase: "test", org: @emu_organization, exclude_suspended: false)
          results = query.execute.results.map { |h| h["_model"] }
          assert_same_elements [@emu_user, @emu_user_suspended, @emu_organization], results
        end

        test "Non-EMU business or org @excluded_suspended is true returns all non-emu non-suspended users and orgs" do
          make_searchable(@emu_user, @emu_user_2, @emu_user_suspended, @non_emu_user, @emu_organization, @emu_organization_2, @non_emu_organization)

          query = Search::Queries::UserLoginQuery.new(phrase: "test", exclude_suspended: true)
          results = query.execute.results.map { |h| h["_model"] }
          assert_same_elements [@non_emu_user, @non_emu_organization], results
        end

        test "Non-EMU business or org @excluded_suspended is false returns non-emu users and orgs" do
          make_searchable(@emu_user, @emu_user_2, @emu_user_suspended, @non_emu_user, @emu_organization, @emu_organization_2, @non_emu_organization)

          query = Search::Queries::UserLoginQuery.new(phrase: "test", exclude_suspended: false)
          results = query.execute.results.map { |h| h["_model"] }
          assert_same_elements [@non_emu_user, @non_emu_organization], results
        end

        test "Non-EMU business search returns only non emu users and orgs" do
          make_searchable(@emu_user, @non_emu_user, @emu_organization, @non_emu_organization)

          query = Search::Queries::UserLoginQuery.new(phrase: "test", business: @non_emu_enterprise)
          results = query.execute.results.map { |h| h["_model"] }
          assert_same_elements [@non_emu_user, @non_emu_organization], results
        end

        test "Non-EMU org search returns only non emu users and orgs" do
          make_searchable(@emu_user, @non_emu_user, @emu_organization, @non_emu_organization)

          query = Search::Queries::UserLoginQuery.new(phrase: "test", org: @non_emu_organization)
          results = query.execute.results.map { |h| h["_model"] }
          assert_same_elements [@non_emu_user, @non_emu_organization], results
        end

        context "#enterprise_id" do
          test "returns nil when not enterprise managed user context" do
            query = Search::Queries::UserLoginQuery.new(current_user: @non_emu_user, phrase: "test")
            refute query.enterprise_id

            query = Search::Queries::UserLoginQuery.new(phrase: "test", business: @non_emu_enterprise)
            refute query.enterprise_id

            query = Search::Queries::UserLoginQuery.new(phrase: "test", org: @non_emu_organization)
            refute query.enterprise_id

            query = Search::Queries::UserLoginQuery.new(phrase: "test")
            refute query.enterprise_id
          end

          test "returns busines_id when context is enterprise managed" do
            query = Search::Queries::UserLoginQuery.new(current_user: @emu_user, phrase: "test")
            assert_equal @emu_enterprise.id, query.enterprise_id

            query = Search::Queries::UserLoginQuery.new(phrase: "test", business: @emu_enterprise)
            assert_equal @emu_enterprise.id, query.enterprise_id

            query = Search::Queries::UserLoginQuery.new(phrase: "test", org: @emu_organization)
            assert_equal @emu_enterprise.id, query.enterprise_id
          end
        end
      end
    end
  end

  test "it returns nil for the highlight" do
    query = Search::Queries::UserLoginQuery.new(phrase: "drewb")

    assert_nil query.build_highlight
  end

  test "it returns nil for the sort" do
    query = Search::Queries::UserLoginQuery.new(phrase: "drewb")

    assert_nil query.build_sort
  end

  test "it returns nil for the filter" do
    query = Search::Queries::UserLoginQuery.new(phrase: "drewb")

    assert_nil query.build_filter
  end

  test "it returns nil for the aggregations" do
    query = Search::Queries::UserLoginQuery.new(phrase: "drewb")

    assert_nil query.build_aggregations
  end

  context "limited to org members" do
    test "when org_member_scope is :all it limits to all org members only" do
      query = Search::Queries::UserLoginQuery.new(phrase: "chip", org: @org, org_member_scope: :all)
      results = query.execute.results.map { |h| h["_model"] }
      assert_same_elements [@chipmunk, @chipmunks], results
    end

    test "when org_member_scope is :public it limits to public org members only" do
      query = Search::Queries::UserLoginQuery.new(phrase: "chip", org: @org, org_member_scope: :public)
      results = query.execute.results.map { |h| h["_model"] }
      assert_equal [@chipmunk], results
    end

    test "builds a all_org_ids filter" do
      query = Search::Queries::UserLoginQuery.new(phrase: "chip", org: @org, org_member_scope: :all)
      expected_filter = {
        bool: {
          must: {
            multi_match: {
              query: "chip",
              fields: ["login^10", "name", "login.ngram^0.8"],
              operator: "AND",
              type: "most_fields",
              analyzer: "lowercase",
            },
          },
          filter: {
            bool: {
              must: {
                term: {
                  all_org_ids: @org.id,
                },
              },
              must_not: {
                exists: {
                  field: :business_id
                }
              }
            },
          },
        },
      }
      assert_equal(expected_filter, query.build_query)
    end

    test "builds a public_org_ids filter" do
      query = Search::Queries::UserLoginQuery.new(phrase: "chip", org: @org, org_member_scope: :public)
      expected_filter = {
        bool: {
          must: {
            multi_match: {
              query: "chip",
              fields: ["login^10", "name", "login.ngram^0.8"],
              operator: "AND",
              type: "most_fields",
              analyzer: "lowercase",
            },
          },
          filter: {
            bool: {
              must: {
                term: {
                  public_org_ids: @org.id,
                },
              },
              must_not: {
                exists: {
                  field: :business_id
                }
              }
            },
          },
        },
      }
      assert_equal(expected_filter, query.build_query)
    end

    if !GitHub.single_business_environment?
      test "builds an all_org_ids filter that includes all business orgs when include_business_orgs is specified" do
        business = create(:business)
        other_org = create(:organization, business: business)
        @org.update(business: business)

        business.reload

        query = Search::Queries::UserLoginQuery.new(phrase: "chip", org: @org, org_member_scope: :all, include_business_orgs: true)

        expected_filter = {
          bool: {
            must: {
              multi_match: {
                query: "chip",
                fields: ["login^10", "name", "login.ngram^0.8"],
                operator: "AND",
                type: "most_fields",
                analyzer: "lowercase",
              },
            },
            filter: {
              bool: {
                must: {
                  terms: {
                    all_org_ids: [@org.id, other_org.id],
                  },
                },
                must_not: {
                  exists: {
                    field: :business_id
                  }
                }
              },
            },
          },
        }

        assert_equal(expected_filter, query.build_query)
      end

      test "builds an all_org_ids and business_id filter that includes all business orgs when include_business_orgs and business are specified" do
        query = Search::Queries::UserLoginQuery.new(phrase: "user", org: @emu_organization, business: @emu_enterprise, org_member_scope: :all)

        expected_filter = {
          bool: {
            must: {
              multi_match: {
                query: "user",
                fields: ["login^10", "name", "login.ngram^0.8"],
                operator: "AND",
                type: "most_fields",
                analyzer: "lowercase",
              },
            },
            filter: {
              bool: {
                must: [
                  {
                    term: {
                      business_id: @emu_enterprise.id
                    }
                  },
                  {
                    term: {
                      all_org_ids: @emu_organization.id,
                    }
                  }
                ]
              }
            }
          }
        }
        assert_equal(expected_filter, query.build_query)
      end
    end
  end
end
