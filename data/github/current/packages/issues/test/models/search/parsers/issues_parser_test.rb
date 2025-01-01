# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchParsersIssuesParserTest < GitHub::TestCase
  setup do
    @parser = ::Search::Parsers::IssuesParser.new
  end

  test "empty input string" do
    tree = @parser.parse("")
    expected_tree = { root: nil }

    assert_equal expected_tree, tree
  end

  context "text term" do
    test "simple term" do
      tree = @parser.parse("emojis")
      expected_tree = { root: { text_term: "emojis" } }

      assert_equal expected_tree, tree
    end

    test "term starting with colon:" do
      tree = @parser.parse(":rainbow:")
      expected_tree = { root: { text_term: ":rainbow:" } }

      assert_equal expected_tree, tree
    end

    test "term with special characters" do
      tree = @parser.parse("@term?")
      expected_tree = { root: { text_term: "@term?" } }

      assert_equal expected_tree, tree
    end

    test "term with backticks" do
      tree = @parser.parse("`code`")
      expected_tree = { root: { text_term: "`code`" } }

      assert_equal expected_tree, tree
    end

    test "i18n term" do
      tree = @parser.parse("fichier_d'en-tête_ログインが必要です")
      expected_tree = { root: { text_term: "fichier_d'en-tête_ログインが必要です" } }

      assert_equal expected_tree, tree
    end

    test "term with parenthesis" do
      tree = @parser.parse("((term_a))")
      expected_tree = { root: { text_term: "term_a" } }

      assert_equal expected_tree, tree
    end

    test "term with parenthesis and spaces" do
      tree = @parser.parse("(( ( term_a)) )")
      expected_tree = { root: { text_term: "term_a" } }

      assert_equal expected_tree, tree
    end
  end

  context "string terms" do
    test "simple quoted term" do
      tree = @parser.parse('"test term"')
      expected_tree = {
        root: {
          text_term: { string: "test term" },
        },
      }

      assert_equal expected_tree, tree
    end

    test "unfinished double quoted term" do
      tree = @parser.parse('"test term')
      expected_tree = {
        root: {
          text_term: { string: "test term" }
        }
      }

      assert_equal expected_tree, tree
    end

    test "double quoted term with special characters and escape sequences" do
      tree = @parser.parse('">> special characters[~`!@#$%^&_+(*){:;}] \"1238\" \\ 01/23/23 >= 987"')
      expected_tree = {
        root: {
          text_term: { string: '>> special characters[~`!@#$%^&_+(*){:;}] \\"1238\\" \\ 01/23/23 >= 987' },
        },
      }

      assert_equal expected_tree, tree
    end

    test "simple single quote in term" do
      tree = @parser.parse("'test term'")
      expected_tree = {
        root: {
          text_term: { string: "test term" }
        }
      }

      assert_equal expected_tree, tree
    end

    test "unfinished single quoted term" do
      tree = @parser.parse("'test term")
      expected_tree = expected_tree = {
        root: {
          text_term: { string: "test term" },
        },
      }

      assert_equal expected_tree, tree
    end

    test "single term with special characters and escape sequences" do
      tree = @parser.parse('\'"special characters": [<>~`!@#$%^&_+(*){:;}] \\\\ \\\'1238\\\' 01/23/23 >= 987\'')
      expected_tree = {
        root: {
          text_term: {
            string: '"special characters": [<>~`!@#$%^&_+(*){:;}] \\\\ \\\'1238\\\' 01/23/23 >= 987',
          },
        },
      }

      assert_equal expected_tree, tree
    end
  end

  context "filter terms" do
    test "simple filter" do
      tree = @parser.parse("type:issue")
      expected_tree = {
          root: {
            filter_term: {
              attribute: "type",
              value: [{ filter_value: "issue" }],
              negative: nil,
            },
        },
      }

      assert_equal expected_tree, tree
    end

    test "filter value with special characters" do
      tree = @parser.parse("label:$:version-?-minor-?:$")
      expected_tree = {
          root: {
            filter_term: {
              attribute: "label",
              value: [{ filter_value: "$:version-?-minor-?:$" }],
              negative: nil,
            },
        },
      }

      assert_equal expected_tree, tree
    end

    test "quoted filter value with space" do
      tree = @parser.parse('label:"Epic One"')
      expected_tree = {
        root: {
          filter_term: {
            attribute: "label",
            value: [{ filter_value: { string: "Epic One" } }],
            negative: nil,
          },
        },
      }


      assert_equal expected_tree, tree
    end

    test "quoted value with emoji" do
      tree = @parser.parse('label:"bug 🐛"')
      expected_tree = {
        root: {
          filter_term: {
            negative: nil,
            attribute: "label",
            value: [{ filter_value: { string: "bug 🐛" } }],
          },
        },
      }

      assert_equal expected_tree, tree
    end

    test "enumerable filter values" do
      tree = @parser.parse("milestone:one,two")
      expected_tree = {
        root: {
          filter_term: {
            attribute: "milestone",
            value: [
              { filter_value: "one" },
              { filter_value: "two" },
            ],
            negative: nil,
          },
        },
      }

      assert_equal expected_tree, tree
    end

    test "enumerable filter values with spaces" do
      tree = @parser.parse('label:bug,wontfix,"epic one"')
      expected_tree = {
        root: {
          filter_term: {
            attribute: "label",
            value: [
              { filter_value: "bug" },
              { filter_value: "wontfix" },
              { filter_value: { string: "epic one" } },
            ],
            negative: nil,
          },
        },
      }

      assert_equal expected_tree, tree
    end

    test "filter with quoted value containing comma" do
      tree = @parser.parse('milestone:"one,two"')
      expected_tree = {
        root: {
          filter_term: {
            attribute: "milestone",
            value: [{ filter_value: { string: "one,two" } }],
            negative: nil,
          },
        },
      }

      assert_equal expected_tree, tree
    end

    test "double quoted filter value" do
      tree = @parser.parse('attribute:"value quoted"')
      expected_tree = {
        root: {
          filter_term: {
            attribute: "attribute",
            value: [
              { filter_value: { string: "value quoted" } },
            ],
            negative: nil,
          },
        },
      }

      assert_equal expected_tree, tree
    end

    test "single quoted filter value" do
      tree = @parser.parse("filter-reaction+:'single,(asdf)[]{}\" #quoted# string?'")
      expected_tree = {
        root: {
          filter_term: {
            attribute: "filter-reaction+",
            value: [{ filter_value: { string: "single,(asdf)[]{}\" #quoted# string?" } }],
            negative: nil,
          },
        },
      }

      assert_equal expected_tree, tree
    end


    test "enumerable with double quoted string and special characters and emojis" do
      tree = @parser.parse('-label:"help wanted",🐙,"~!@#$^&^`&*()-_=+[]{}:;",<漢字>P1,bug🐛')
      expected_tree = {
        root: {
          filter_term: {
            negative: "-",
            attribute: "label",
            value: [
              { filter_value: { string: "help wanted" } },
              { filter_value: "🐙" },
              { filter_value: { string: "~!@#$^&^`&*()-_=+[]{}:;" } },
              { filter_value: "<漢字>P1" },
              { filter_value: "bug🐛" },
            ],
          },
        },
      }

      assert_equal expected_tree, tree
    end

    test "implicit and of filter value with special characters" do
      tree = @parser.parse("label:@test=123?123%$^?!@~`:: simple_filter:value_a")
      expected_tree = {
        root: {
          and: {
            left: {
              filter_term: {
                attribute: "label",
                value: [{ filter_value: "@test=123?123%$^?!@~`::" }],
                negative: nil,
              }
            },
            right: {
              filter_term: {
                attribute: "simple_filter",
                value: [{ filter_value: "value_a" }],
                negative: nil,
              }
            },
          },
        },
      }

      assert_equal expected_tree, tree
    end

    test "qualifier special characters stress test" do
      tree = @parser.parse("type:@test= filter-reaction+:'single #quoted# string?' q:a0%$^?!@~`: escaped:\"inner \\\" escape quotation\"")
      expected_tree = {
        root: {
          and: {
            left: {
              filter_term: {
                attribute: "type",
                value: [{ filter_value: "@test=" }],
                negative: nil,
              },
            },
            right: {
              and: {
                left: {
                  filter_term: {
                    attribute: "filter-reaction+",
                    value: [{ filter_value: { string: "single #quoted# string?" } }],
                    negative: nil,
                  }
                },
                right: {
                  and: {
                    left: {
                      filter_term: {
                        attribute: "q",
                        value: [{ filter_value: "a0%$^?!@~`:" }],
                        negative: nil,
                      },
                    },
                    right: {
                      filter_term: {
                        attribute: "escaped",
                        value: [{ filter_value: { string: 'inner \\" escape quotation' } }],
                        negative: nil,
                      },
                    },
                  },
                },
              },
            },
          },
        },
      }

      assert_equal expected_tree, tree
    end
  end

  context "reserved keywords" do
    test "AND keyword fail to match term rule" do
      assert_raises(Parslet::ParseFailed) do
        tree = @parser.parse("and")
      end
    end

    test "term can start with AND" do
      query_a = "android"
      expected_tree_a = {
        root: { text_term: "android" },
      }
      tree_a = @parser.parse(query_a)

      assert_equal expected_tree_a, tree_a

      query_b = "test android and andromeda_version"
      expected_tree_b = {
        root: {
          and: {
            left: { text_term: "test" },
            right: {
              and: {
                left: { text_term: "android" },
                right: { text_term: "andromeda_version" },
              },
            },
          },
        },
      }
      tree_b = @parser.parse(query_b)

      assert_equal expected_tree_b, tree_b
    end

    test "AND is never parsed inside a quoted string" do
      query = 'test "android and andromeda_version" \'anderson and oregon\''
      expected_tree = {
        root: {
          and: {
            left: { text_term: "test" },
            right: {
              and: {
                left: { text_term: { string: "android and andromeda_version" } },
                right: { text_term: { string: "anderson and oregon" } },
              }
            },
          },
        },
      }
      tree = @parser.parse(query)

      assert_equal expected_tree, tree
    end

    test "OR keyword fail to match term rule" do
      assert_raises(Parslet::ParseFailed) do
        tree = @parser.parse("OR")
      end
    end

    test "term can start with OR" do
      query_a = "organization"
      expected_tree_a = {
        root: { text_term: "organization" },
      }
      tree_a = @parser.parse(query_a)

      assert_equal expected_tree_a, tree_a

      query_b = "test orion or oracle"
      expected_tree_b = {
        root: {
          or: {
            left: {
              and: {
                left: { text_term: "test" },
                right: { text_term: "orion" },
              },
            },
            right: { text_term: "oracle" },
          },
        },
      }
      tree_b = @parser.parse(query_b)

      assert_equal expected_tree_b, tree_b
    end

    test "OR is never parsed inside a quoted string" do
      query = "test 'orion or oracle' \"origin or and\""
      expected_tree = {
        root: {
          and: {
            left: { text_term: "test" },
            right: {
              and: {
                left: {
                  text_term: { string:  "orion or oracle" },
                },
                right: {
                  text_term: { string: "origin or and" },
                },
              },
            }
          },
        },
      }
      tree = @parser.parse(query)

      assert_equal expected_tree, tree
    end
  end

  context "implicit and" do
    test "multiple terms no parentheses" do
      tree = @parser.parse("multiple terms")
      expected_tree = {
        root: {
          and: {
            left: { text_term: "multiple" },
            right: { text_term: "terms" },
          },
        },
      }

      assert_equal expected_tree, tree
    end

    test "multiple terms with surrounding parentheses" do
      tree = @parser.parse("( ( multiple ) (( terms) ) )")
      expected_tree = {
        root: {
          and: {
            left: { text_term: "multiple" },
            right: { text_term: "terms" },
          },
        },
      }

      assert_equal expected_tree, tree
    end

    test "qualifier with term" do
      tree = @parser.parse("type:issue term")
      expected_tree = {
        root: {
          and: {
            left: {
              filter_term: {
                attribute: "type",
                value: [{ filter_value: "issue" }],
                negative: nil,
              },
            },
            right: { text_term: "term" },
          },
        },
      }

      assert_equal expected_tree, tree
    end

    test "implicit and with single quoted terms" do
      tree = @parser.parse("is:issue state:open 'feature flag'")
      expected_tree = {
        root: {
          and: {
            left: {
              filter_term: {
                attribute: "is",
                value: [{ filter_value: "issue" }],
                negative: nil,
              }
            },
            right: {
              and: {
                left: {
                  filter_term: {
                    attribute: "state",
                    value: [{ filter_value: "open" }],
                    negative: nil,
                  }
                },
                right: { text_term: { string: "feature flag" } },
              },
            },
          },
        },
      }

      assert_equal expected_tree, tree
    end
  end

  test "and operation" do
    tree = @parser.parse("(type:issue AND opened:recently)")
    expected_tree = {
      root: {
        and: {
          left: {
            filter_term: {
              attribute: "type",
              value: [{ filter_value: "issue" }],
              negative: nil,
            },
          },
          right: {
            filter_term: {
              attribute: "opened",
              value: [{ filter_value: "recently" }],
              negative: nil,
            },
          },
        },
      },
    }

    assert_equal expected_tree, tree
  end

  test "and operation without parens" do
    tree = @parser.parse("type:issue AND opened:recently")
    expected_tree = {
      root: {
        and: {
          left: {
            filter_term: {
              attribute: "type",
              value: [{ filter_value: "issue" }],
              negative: nil,
            },
          },
          right: {
            filter_term: {
              attribute: "opened",
              value: [{ filter_value: "recently" }],
              negative: nil,
            },
          },
        },
      },
    }

    assert_equal expected_tree, tree
  end

  test "or operation without parens" do
    tree = @parser.parse("opened:recently OR author:dewski")
    expected_tree = {
      root: {
        or: {
          left: {
            filter_term: {
              attribute: "opened",
              value: [{ filter_value: "recently" }],
              negative: nil,
            },
          },
          right: {
            filter_term: {
              attribute: "author",
              value: [{ filter_value: "dewski" }],
              negative: nil,
            },
          },
        },
      },
    }

    assert_equal expected_tree, tree
  end

  test "or conditions with parens" do
    tree = @parser.parse("(opened:recently OR author:dewski)")
    expected_tree = {
      root: {
        or: {
          left: {
            filter_term: {
              attribute: "opened",
              value: [{ filter_value: "recently" }],
              negative: nil,
            },
          },
          right: {
            filter_term: {
              attribute: "author",
              value: [{ filter_value: "dewski" }],
              negative: nil,
            },
          },
        },
      },
    }

    assert_equal expected_tree, tree
  end

  test "nested conditions" do
    tree = @parser.parse("(issue AND (author:@me AND (attribute:value OR query:filter)))")
    expected_tree = {
      root: {
        and: {
          left: { text_term: "issue" },
          right: {
            and: {
              left: {
                filter_term: {
                  attribute: "author",
                  value: [{ filter_value: "@me" }],
                  negative: nil,
                },
              },
              right: {
                or: {
                  left: {
                    filter_term: {
                      attribute: "attribute",
                      value: [{ filter_value: "value" }],
                      negative: nil,
                    },
                  },
                  right: {
                    filter_term: {
                      attribute: "query",
                      value: [{ filter_value: "filter" }],
                      negative: nil,
                    },
                  },
                },
              },
            },
          },
        },
      },
    }

    assert_equal expected_tree, tree
  end

  test "three conditions without parens" do
    tree = @parser.parse("(issue OR author:me AND attribute:value)")
    expected_tree = {
      root: {
        or:  {
          left: { text_term: "issue" },
          right: {
            and: {
              left: {
                filter_term: {
                  attribute: "author",
                  value: [{ filter_value: "me" }],
                  negative: nil,
                },
              },
              right: {
                filter_term: {
                  attribute: "attribute",
                  value: [{ filter_value: "value" }],
                  negative: nil,
                },
              },
            },
          },
        },
      },
    }

    assert_equal expected_tree, tree
  end

  test "negative qualifiers" do
    tree = @parser.parse("type:issue AND -opened:recently")
    expected_tree = {
      root: {
        and: {
          left: {
            filter_term: {
              attribute: "type",
              value: [{ filter_value: "issue" }],
              negative: nil,
            }
          },
          right: {
            filter_term: {
              attribute: "opened",
              value: [{ filter_value: "recently" }],
              negative: "-",
            },
          },
        },
      },
    }

    assert_equal expected_tree, tree
  end

  test "implicit and between terms" do
    tree = @parser.parse("label:bug OR author:monalisa sort:created-desc")
    expected_tree = {
      root: {
        or: {
          left: {
            filter_term: {
              negative: nil,
              attribute: "label",
              value: [{ filter_value: "bug" }],
            },
          },
          right: {
            and: {
              left: {
                filter_term: {
                  negative: nil,
                  attribute: "author",
                  value: [{ filter_value: "monalisa" }],
                },
              },
              right: {
                filter_term: {
                  negative: nil,
                  attribute: "sort",
                  value: [{ filter_value: "created-desc" }],
                },
              },
            },
          },
        },
      },
    }

    assert_equal expected_tree, tree
  end

  test "no qualifier" do
    tree = @parser.parse("type:issue AND no:milestone")
    expected_tree = {
      root: {
        and: {
          left: {
            filter_term: {
              attribute: "type",
              value: [{ filter_value: "issue" }],
              negative: nil,
            },
          },
          right: {
            filter_term: {
              missing: "no",
              attribute: "milestone"
            },
          },
        },
      },
    }

    assert_equal expected_tree, tree
  end

  test "enumerable terms with spaces AND another qualifier" do
    tree = @parser.parse('label:bug,wontfix,"epic one" AND state:open')
    expected_tree = {
      root: {
        and: {
          left: {
            filter_term: {
              negative: nil,
              attribute: "label",
              value: [
                { filter_value: "bug" },
                { filter_value: "wontfix" },
                { filter_value: { string: "epic one" } },
              ],
            },
          },
          right: {
            filter_term: {
              negative: nil,
              attribute: "state",
              value: [{ filter_value: "open" }],
            },
          },
        },
      },
    }

    assert_equal expected_tree, tree
  end

  test "quoted value with emoji and another qualifier" do
    tree = @parser.parse('label:"bug 🐛" label:wontfix')
    expected_tree = {
      root: {
        and: {
          left: {
            filter_term: {
              negative: nil,
              attribute: "label",
              value: [{ filter_value: { string: "bug 🐛" } }],
            }
          },
          right: {
            filter_term: {
              negative: nil,
              attribute: "label",
              value: [{ filter_value: "wontfix" }],
            }
          },
        },
      },
    }

    assert_equal expected_tree, tree
  end

  # At the time of writing we do not yet support a quoted value in the middle of the list with a space. This is a
  # known limitation and is being tracked as part of https://github.com/github/collaboration-workflows-flex/issues/740
  test "quoted value in the middle of a comma separated list of values" do
    tree = @parser.parse('label:wontfix,"bug 🐛",enhancement review-requested:monalisa')
    expected_tree = {
      root: {
        and: {
          left: {
            filter_term: {
              negative: nil,
              attribute: "label",
              value: [
                { filter_value: "wontfix" },
                { filter_value: { string: "bug 🐛" } },
                { filter_value: "enhancement" },
              ],
            },
          },
          right: {
            filter_term: {
              negative: nil,
              attribute: "review-requested",
              value: [{ filter_value: "monalisa" }],
            },
          },
        },
      },
    }

    assert_equal expected_tree, tree
  end

  test "values with greater than or less than symbols" do
    tree = @parser.parse("created:>2021-04-21 updated:<2021-04-21")
    expected_tree = {
      root: {
        and: {
          left: {
            filter_term: {
              negative: nil,
              attribute: "created",
              value: [{ filter_value: ">2021-04-21" }],
            },
          },
          right: {
            filter_term: {
              negative: nil,
              attribute: "updated",
              value: [{ filter_value: "<2021-04-21" }],
            },
          },
        },
      },
    }

    assert_equal expected_tree, tree
  end

  test "values with greater than or less than synbols in quotes" do
    tree = @parser.parse("created:\">2021-04-21\" updated:\"<2021-04-21\"")
    expected_tree = {
      root: {
        and: {
          left: {
            filter_term: {
              negative: nil,
              attribute: "created",
              value: [{ filter_value: { string: ">2021-04-21" } }],
            },
          },
          right: {
            filter_term: {
              negative: nil,
              attribute: "updated",
              value: [{ filter_value: { string: "<2021-04-21" } }],
            },
          },
        },
      },
    }

    assert_equal expected_tree, tree
  end

  test "implicit and supports explicit AND and OR operators" do
    tree = @parser.parse("(label:a assignee:steves OR some_term) OR (label:b no:assignee AND -filter:a,b,c)")
    expected_tree = {
      root: {
        or: {
          left: {
            or: {
              left: {
                and: {
                  left: {
                    filter_term: {
                      negative: nil,
                      attribute: "label",
                      value: [{ filter_value: "a" }],
                    },
                  },
                  right: {
                    filter_term: {
                      negative: nil,
                      attribute: "assignee",
                      value: [{ filter_value: "steves" }],
                    }
                  },
                },
              },
              right: { text_term: "some_term" }
            },
          },
          right: {
            and: {
              left: {
                filter_term: {
                  negative: nil,
                  attribute: "label",
                  value: [{ filter_value: "b" }],
                },
              },
              right: {
                and: {
                  left: {
                    filter_term: {
                      missing: "no",
                      attribute: "assignee",
                    },
                  },
                  right: {
                    filter_term: {
                      negative: "-",
                      attribute: "filter",
                      value: [
                        { filter_value: "a" },
                        { filter_value: "b" },
                        { filter_value: "c" },
                      ],
                    },
                  },
                },
              },
            },
          },
        },
      },
    }

    assert_equal expected_tree, tree
  end

  test "implicit nested ANDs are parsed correctly" do
    tree = @parser.parse("(label:a assignee:steves) OR (label:b no:assignee)")
    expected_tree = {
      root: {
        or: {
          left: {
            and: {
              left: {
                filter_term: {
                  negative: nil,
                  attribute: "label",
                  value: [{ filter_value: "a" }],
                },
              },
              right: {
                filter_term: {
                  negative: nil,
                  attribute: "assignee",
                  value: [{ filter_value: "steves" }],
                },
              },
            },
          },
          right: {
            and: {
              left: {
                filter_term: {
                  negative: nil,
                  attribute: "label",
                  value: [{ filter_value: "b" }],
                },
              },
              right: {
                filter_term: {
                  missing: "no",
                  attribute: "assignee",
                },
              },
            },
          },
        },
      },
    }

    assert_equal expected_tree, tree
  end

  test "mix of implicit and explicit ANDs are parsed correctly" do
    tree = @parser.parse("(label:a assignee:steves) OR ((label:b AND no:assignee) state:open)")
    expected_tree = {
      root: {
        or: {
          left: {
            and: {
              left: {
                filter_term: {
                  negative: nil,
                  attribute: "label",
                  value: [{ filter_value: "a" }],
                },
              },
              right: {
                filter_term: {
                  negative: nil,
                  attribute: "assignee",
                  value: [{ filter_value: "steves" }],
                }
              },
            },
          },
          right: {
            and: {
              left: {
                and: {
                  left: {
                    filter_term: {
                      negative: nil,
                      attribute: "label",
                      value: [{ filter_value: "b" }],
                    },
                  },
                  right: {
                    filter_term: {
                      missing: "no",
                      attribute: "assignee",
                    }
                  }
                }
              },
              right: {
                filter_term: {
                  negative: nil,
                  attribute: "state",
                  value: [{ filter_value: "open" }],
                }
              },
            },
          },
        }
      },
    }

    assert_equal expected_tree, tree
  end
end
