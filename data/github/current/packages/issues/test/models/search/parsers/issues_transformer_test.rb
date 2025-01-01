# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchParsersIssuesTransformerTest < GitHub::TestCase
  setup do
    @parser = ::Search::Parsers::IssuesParser.new
    @transformer = ::Search::Parsers::IssuesTransformer.new
  end

  test "empty input string" do
    parser_tree = @parser.parse("")
    transform_tree = @transformer.apply(parser_tree)
    expected_parser_tree = { root: nil }

    assert_equal expected_parser_tree, parser_tree
    assert_equal parser_tree, transform_tree
  end

  test "simple term tree remain the same" do
    parser_tree = @parser.parse("emojis")
    transform_tree = @transformer.apply(parser_tree)
    expected_parser_tree = { root: { text_term: "emojis" } }

    assert_equal expected_parser_tree, parser_tree
    assert_equal parser_tree, transform_tree
  end

  test "string nodes are unwrapped and unescaped" do
    parser_tree = @parser.parse('"test term \\""')
    transform_tree = @transformer.apply(parser_tree)

    expected_parser_tree = {
      root: {
        text_term: { string: 'test term \\"' },
      },
    }
    expected_transform_tree = { root: { text_term: 'test term "', } }

    assert_equal expected_parser_tree, parser_tree
    assert_equal expected_transform_tree, transform_tree
  end

  test "filter value nodes are unwrapped" do
    parser_tree = @parser.parse("type:issue")
    transform_tree = @transformer.apply(parser_tree)

    expected_parser_tree = {
        root: {
          filter_term: {
            attribute: "type",
            value: [{ filter_value: "issue" }],
            negative: nil,
          },
      },
    }
    expected_transform_tree = {
      root: {
        filter_term: {
          attribute: "type",
          value: ["issue"],
          negative: nil,
        },
      },
    }

    assert_equal expected_parser_tree, parser_tree
    assert_equal expected_transform_tree, transform_tree
  end

  test "string filter values are unwrapped" do
    parser_tree = @parser.parse('label:"Epic One"')
    transform_tree = @transformer.apply(parser_tree)

    expected_parser_tree = {
      root: {
        filter_term: {
          attribute: "label",
          value: [{ filter_value: { string: "Epic One" } }],
          negative: nil,
        },
      },
    }
    expected_transform_tree = {
      root: {
        filter_term: {
          attribute: "label",
          value: ["Epic One"],
          negative: nil,
        },
      },
    }

    assert_equal expected_parser_tree, parser_tree
    assert_equal expected_transform_tree, transform_tree
  end

  test "enumerable filter values are unwrapped" do
    parser_tree = @parser.parse("label:bug,'help wanted'")
    transform_tree = @transformer.apply(parser_tree)

    expected_parser_tree = {
      root: {
        filter_term: {
          attribute: "label",
          value: [
            { filter_value: "bug" },
            { filter_value: { string: "help wanted" } },
          ],
          negative: nil,
        },
      },
    }
    expected_transform_tree = {
      root: {
        filter_term: {
          attribute: "label",
          value: ["bug", "help wanted"],
          negative: nil,
        },
      },
    }

    assert_equal expected_parser_tree, parser_tree
    assert_equal expected_transform_tree, transform_tree
  end

  test "implicit AND terms are reduced to array" do
    parser_tree = @parser.parse("term_a term_b")
    transform_tree = @transformer.apply(parser_tree)

    expected_parser_tree = {
      root: {
        and: {
          left: { text_term: "term_a" },
          right: { text_term: "term_b" },
        },
      },
    }
    expected_transform_tree = {
      root: {
        and: [
          { text_term: "term_a" },
          { text_term: "term_b" }
        ],
      },
    }

    assert_equal expected_parser_tree, parser_tree
    assert_equal expected_transform_tree, transform_tree
  end

  test "nested implicit AND terms are reduced to array" do
    parser_tree = @parser.parse("term_a term_b (term_c term_d) term_e")
    transform_tree = @transformer.apply(parser_tree)

    expected_parser_tree = {
      root: {
        and: {
          left: { text_term: "term_a" },
          right: {
            and: {
              left: { text_term: "term_b" },
              right: {
                and: {
                  left: {
                    and: {
                      left: { text_term: "term_c" },
                      right: { text_term: "term_d" },
                    },
                  },
                  right: { text_term: "term_e" },
                },
              },
            },
          },
        },
      },
    }
    expected_transform_tree = {
      root: {
        and: [
          { text_term: "term_a" },
          { text_term: "term_b" },
          { text_term: "term_c" },
          { text_term: "term_d" },
          { text_term: "term_e" },
        ],
      },
    }

    assert_equal expected_parser_tree, parser_tree
    assert_equal expected_transform_tree, transform_tree
  end

  test "explicit AND terms are reduced to array" do
    parser_tree = @parser.parse("term_a AND term_b")
    transform_tree = @transformer.apply(parser_tree)

    expected_parser_tree = {
      root: {
        and: {
          left: { text_term: "term_a" },
          right: { text_term: "term_b" },
        },
      },
    }
    expected_transform_tree = {
      root: {
        and: [
          { text_term: "term_a" },
          { text_term: "term_b" }
        ],
      },
    }

    assert_equal expected_parser_tree, parser_tree
    assert_equal expected_transform_tree, transform_tree
  end

  test "mix of explicit and implicis AND terms are reduced to the same array" do
    parser_tree = @parser.parse("term_a AND term_b term_c AND (term_d term_e)")
    transform_tree = @transformer.apply(parser_tree)

    expected_parser_tree = {
      root: {
        and: {
          left: { text_term: "term_a" },
          right: {
            and: {
              left: { text_term: "term_b" },
              right: {
                and: {
                  left: { text_term: "term_c" },
                  right: {
                    and: {
                      left: { text_term: "term_d" },
                      right: { text_term: "term_e" },
                    },
                  },
                },
              },
            },
          },
        },
      },
    }
    expected_transform_tree = {
      root: {
        and: [
          { text_term: "term_a" },
          { text_term: "term_b" },
          { text_term: "term_c" },
          { text_term: "term_d" },
          { text_term: "term_e" },
        ],
      },
    }

    assert_equal expected_parser_tree, parser_tree
    assert_equal expected_transform_tree, transform_tree
  end

  test "OR terms are reduced to array" do
    parser_tree = @parser.parse("term_a OR term_b")
    transform_tree = @transformer.apply(parser_tree)

    expected_parser_tree = {
      root: {
        or: {
          left: { text_term: "term_a" },
          right: { text_term: "term_b" },
        },
      },
    }
    expected_transform_tree = {
      root: {
        or: [
          { text_term: "term_a" },
          { text_term: "term_b" }
        ],
      },
    }

    assert_equal expected_parser_tree, parser_tree
    assert_equal expected_transform_tree, transform_tree
  end

  test "nested OR terms are reduced to array" do
    parser_tree = @parser.parse("term_a OR term_b OR (term_c OR term_d) OR term_e")
    transform_tree = @transformer.apply(parser_tree)

    expected_parser_tree = {
      root: {
        or: {
          left: { text_term: "term_a" },
          right: {
            or: {
              left: { text_term: "term_b" },
              right: {
                or: {
                  left: {
                    or: {
                      left: { text_term: "term_c" },
                      right: { text_term: "term_d" },
                    },
                  },
                  right: { text_term: "term_e" },
                },
              },
            },
          },
        },
      },
    }
    expected_transform_tree = {
      root: {
        or: [
          { text_term: "term_a" },
          { text_term: "term_b" },
          { text_term: "term_c" },
          { text_term: "term_d" },
          { text_term: "term_e" },
        ],
      },
    }

    assert_equal expected_parser_tree, parser_tree
    assert_equal expected_transform_tree, transform_tree
  end

  test "mix of AND and OR terms are reduced to arrays that keep precedence order" do
    parser_tree = @parser.parse("term_a AND term_b OR term_c (term_d OR term_e) term_f")
    transform_tree = @transformer.apply(parser_tree)

    expected_parser_tree = {
      root: {
        or: {
          left: {
            and: {
              left: { text_term: "term_a" },
              right: { text_term: "term_b" },
            }
          },
          right: {
            and: {
              left: { text_term: "term_c" },
              right: {
                and: {
                  left: {
                    or: {
                      left: { text_term: "term_d" },
                      right: { text_term: "term_e" },
                    },
                  },
                  right: { text_term: "term_f" },
                },
              },
            },
          },
        },
      },
    }
    expected_transform_tree = {
      root: {
        or: [
          { and: [
            { text_term: "term_a" },
            { text_term: "term_b" },
          ] },
          { and: [
            { text_term: "term_c" },
            { or: [
              { text_term: "term_d" },
              { text_term: "term_e" },
            ] },
            { text_term: "term_f" },
          ] },
        ],
      },
    }

    assert_equal expected_parser_tree, parser_tree
    assert_equal expected_transform_tree, transform_tree
  end

  test "mix of AND and OR with different term types are reduced to arrays that keep precedence order" do
    parser_tree = @parser.parse(<<-INPUT_QUERY
      label:bug AND "double quoted"
      OR milestone:one,two,'version 1.0'
      (assignee:krhkt OR assignee:steves) [BugFix]
      AND (created:>=@now-7d OR updated:>=@now-5d)
      INPUT_QUERY
    )
    transform_tree = @transformer.apply(parser_tree)

    expected_parser_tree = {
      root: {
        or: {
          left: {
            and: {
              left: {
                filter_term: {
                  negative: nil,
                  attribute: "label",
                  value: [{ filter_value: "bug" }],
                },
              },
              right: { text_term: { string: "double quoted" } },
            },
          },
          right: {
            and: {
              left: {
                filter_term: {
                  negative: nil,
                  attribute: "milestone",
                  value: [
                    { filter_value: "one" },
                    { filter_value: "two" },
                    { filter_value: { string: "version 1.0" } },
                  ],
                },
              },
              right: {
                and: {
                  left: {
                    or: {
                      left: {
                        filter_term: {
                          negative: nil,
                          attribute: "assignee",
                          value: [{ filter_value: "krhkt" }],
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
                      left: { text_term: "[BugFix]" },
                      right: {
                        or: {
                          left: {
                            filter_term: {
                              negative: nil,
                              attribute: "created",
                              value: [{ filter_value: ">=@now-7d" }],
                            },
                          },
                          right: {
                            filter_term: {
                              negative: nil,
                              attribute: "updated",
                              value: [{ filter_value: ">=@now-5d" }],
                            },
                          },
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    }
    expected_transform_tree = {
      root: {
        or: [
          { and: [
              { filter_term: { negative: nil, attribute: "label", value: ["bug"] } },
              { text_term: "double quoted" },
            ],
          },
          { and: [
            { filter_term: { negative: nil, attribute: "milestone", value: ["one", "two", "version 1.0"] } },
            { or: [
              { filter_term: { negative: nil, attribute: "assignee", value: ["krhkt"] } },
              { filter_term: { negative: nil, attribute: "assignee", value: ["steves"] } },
            ] },
            { text_term: "[BugFix]" },
            { or: [
              { filter_term: { negative: nil, attribute: "created", value: [">=@now-7d"] } },
              { filter_term: { negative: nil, attribute: "updated", value: [">=@now-5d"] } },
            ] },
          ] },
        ],
      },
    }

    assert_equal expected_parser_tree, parser_tree
    assert_equal expected_transform_tree, transform_tree
  end
end
