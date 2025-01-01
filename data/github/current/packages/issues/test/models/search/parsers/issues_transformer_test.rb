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

  test "double quoted string doesn't change apostrophe" do
    parser_tree = @parser.parse("\"Mona's\"")
    transform_tree = @transformer.apply(parser_tree)

    expected_parser_tree = {
      root: {
        quoted_text_term: { string: "Mona's" },
      },
    }
    expected_transform_tree = { root: { text_term: '"Mona\'s"' } }

    assert_equal expected_parser_tree, parser_tree
    assert_equal expected_transform_tree, transform_tree
  end

  test "single quoted strings and its escaped sequences are normalized to double quoted strings" do
    search_with_single_quoted_string = "'user\\'s \"carts\"'"
    parser_tree = @parser.parse(search_with_single_quoted_string)
    transform_tree = @transformer.apply(parser_tree)

    expected_parser_tree = {
      root: {
        quoted_text_term: { string: "user\\'s \"carts\"" },
      },
    }
    expected_transform_tree = { root: { text_term: "\"user's  carts \"" } }

    assert_equal expected_parser_tree, parser_tree
    assert_equal expected_transform_tree, transform_tree
  end

  test "apostrophes and escaped quotation mark in double quoted string are not substituted" do
    search_with_double_quoted_string = '"it\'s a test\\""'
    parser_tree = @parser.parse(search_with_double_quoted_string)
    transform_tree = @transformer.apply(parser_tree)

    expected_parser_tree = {
      root: {
        quoted_text_term: { string: "it's a test\\\"" },
      },
    }
    expected_transform_tree = { root: { text_term: "\"it's a test \"" } }

    assert_equal expected_parser_tree, parser_tree
    assert_equal expected_transform_tree, transform_tree
  end

  test "string nodes are unwrapped and unescaped" do
    parser_tree = @parser.parse('"test term \\""')
    transform_tree = @transformer.apply(parser_tree)

    expected_parser_tree = {
      root: {
        quoted_text_term: { string: 'test term \\"' },
      },
    }
    expected_transform_tree = { root: { text_term: '"test term  "', } }

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
    parser_tree = @parser.parse("label:bug,'help wanted','release \"preview\"")
    transform_tree = @transformer.apply(parser_tree)

    expected_parser_tree = {
      root: {
        filter_term: {
          attribute: "label",
          value: [
            { filter_value: "bug" },
            { filter_value: { string: "help wanted" } },
            { filter_value: { string: "release \"preview\"" } },
          ],
          negative: nil,
        },
      },
    }
    expected_transform_tree = {
      root: {
        filter_term: {
          attribute: "label",
          value: ["bug", "help wanted", "release \"preview\""],
          negative: nil,
        },
      },
    }

    assert_equal expected_parser_tree, parser_tree
    assert_equal expected_transform_tree, transform_tree
  end

  test "enumerable filter quoted values escape sequences are normalized" do
    parser_tree = @parser.parse("label:bug,'moore\\'s \"law',\"\\\"obsolete\\\" methods\"")
    transform_tree = @transformer.apply(parser_tree)

    expected_parser_tree = {
      root: {
        filter_term: {
          attribute: "label",
          value: [
            { filter_value: "bug" },
            { filter_value: { string: "moore\\'s \"law" } },
            { filter_value: { string: "\\\"obsolete\\\" methods" } },
          ],
          negative: nil,
        },
      },
    }
    expected_transform_tree = {
      root: {
        filter_term: {
          attribute: "label",
          value: ["bug", "moore's \"law", "\"obsolete\" methods"],
          negative: nil,
        },
      },
    }

    assert_equal expected_parser_tree, parser_tree
    assert_equal expected_transform_tree, transform_tree
  end

  test "adjacent text terms are joined into a single text term" do
    parser_tree = @parser.parse("term_a term_b AND term_c (term_d term_e AND term_f) AND term_g")
    transform_tree = @transformer.apply(parser_tree)

    expected_parser_tree = {
      root: {
        and: {
          left: { text_term: "term_a" },
          right: {
            and: {
              left: { text_term: "term_b" },
              explicit_operator: "AND",
              right: {
                and: {
                  left: { text_term: "term_c" },
                  right: {
                    and: {
                      left: {
                        and: {
                          left: { text_term: "term_d" },
                          right: {
                            and: {
                              left: { text_term: "term_e" },
                              explicit_operator: "AND",
                              right: { text_term: "term_f" },
                            },
                          },
                        },
                      },
                      explicit_operator: "AND",
                      right: { text_term: "term_g" },
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
      root: { text_term: "term_a term_b term_c term_d term_e term_f term_g" },
    }

    assert_equal expected_parser_tree, parser_tree
    assert_equal expected_transform_tree, transform_tree
  end

  test "adjacent text terms are only joined together if they're not and exact text term" do
    parser_tree = @parser.parse("term_a term_b (\"1st exact match term\" term_c) AND '2nd exact match term'")
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
                      left: { quoted_text_term: { string: "1st exact match term" } },
                      right: { text_term: "term_c" }
                    },
                  },
                  explicit_operator: "AND",
                  right: { quoted_text_term: { string: "2nd exact match term" } },
                },
              },
            },
          },
        },
      },
    }
    expected_transform_tree = {
      root: {
        text_term: "term_a term_b \"1st exact match term\" term_c \"2nd exact match term\""
      },
    }

    assert_equal expected_parser_tree, parser_tree
    assert_equal expected_transform_tree, transform_tree
  end

  test "implicit AND'd terms are reduced to array" do
    parser_tree = @parser.parse("term_a in:title")
    transform_tree = @transformer.apply(parser_tree)

    expected_parser_tree = {
      root: {
        and: {
          left: { text_term: "term_a" },
          right: {
            filter_term: {
              attribute: "in",
              value: [{ filter_value: "title" }],
              negative: nil,
            },
          },
        },
      },
    }
    expected_transform_tree = {
      root: {
        and: [
          { text_term: "term_a" },
          { filter_term: { negative: nil, attribute: "in", value: ["title"] } },
        ],
      },
    }

    assert_equal expected_parser_tree, parser_tree
    assert_equal expected_transform_tree, transform_tree
  end

  test "multiple text terms with in: fields are reduced to an array" do
    parser_tree = @parser.parse("term_a term_b in:title")
    transform_tree = @transformer.apply(parser_tree)

    expected_parser_tree = {
      root: {
        and: {
          left: { text_term: "term_a" },
          right: {
            and: {
              left: { text_term: "term_b" },
              right: {
                filter_term: {
                  negative: nil,
                  attribute: "in",
                  value: [{ filter_value: "title" }]
                }
              }
            }
          }
        }
      }
    }
    expected_transform_tree = {
      root: {
        and: [
          { text_term: "term_a term_b" },
          { filter_term: { negative: nil, attribute: "in", value: ["title"] } },
        ],
      },
    }

    assert_equal expected_parser_tree, parser_tree
    assert_equal expected_transform_tree, transform_tree
  end

  test "nested implicit AND'd terms are reduced to array" do
    parser_tree = @parser.parse("term_a label:bug (term_c in:body) term_e")
    transform_tree = @transformer.apply(parser_tree)

    expected_parser_tree = {
      root: {
        and: {
          left: { text_term: "term_a" },
          right: {
            and: {
              left: {
                filter_term: {
                  attribute: "label",
                  value: [{ filter_value: "bug" }],
                  negative: nil,
                },
              },
              right: {
                and: {
                  left: {
                    and: {
                      left: { text_term: "term_c" },
                      right: {
                        filter_term: {
                          attribute: "in",
                          value: [{ filter_value: "body" }],
                          negative: nil,
                        },
                      },
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
          { filter_term: { negative: nil, attribute: "label", value: ["bug"] } },
          { text_term: "term_c" },
          { filter_term: { negative: nil, attribute: "in", value: ["body"] } },
          { text_term: "term_e" },
        ],
      },
    }
    assert_equal expected_parser_tree, parser_tree
    assert_equal expected_transform_tree, transform_tree
  end

  test "explicit AND'd terms are reduced to array" do
    parser_tree = @parser.parse("term_a AND label:bug")
    transform_tree = @transformer.apply(parser_tree)

    expected_parser_tree = {
      root: {
        and: {
          left: { text_term: "term_a" },
          explicit_operator: "AND",
          right: {
            filter_term: {
              attribute: "label",
              value: [{ filter_value: "bug" }],
              negative: nil,
            },
          },
        },
      },
    }
    expected_transform_tree = {
      root: {
        and: [
          { text_term: "term_a" },
          { filter_term: { negative: nil, attribute: "label", value: ["bug"] } },
        ],
      },
    }
    assert_equal expected_parser_tree, parser_tree
    assert_equal expected_transform_tree, transform_tree
  end

  test "mix of explicit and implicit AND'd terms are reduced to the same array" do
    parser_tree = @parser.parse("term_a AND label:bug term_c AND (author:monalisa term_e)")
    transform_tree = @transformer.apply(parser_tree)

    expected_parser_tree = {
      root: {
        and: {
          left: { text_term: "term_a" },
          explicit_operator: "AND",
          right: {
            and: {
              left: {
                filter_term: {
                  attribute: "label",
                  value: [{ filter_value: "bug" }],
                  negative: nil,
                }
              },
              right: {
                and: {
                  left: { text_term: "term_c" },
                  explicit_operator: "AND",
                  right: {
                    and: {
                      left: {
                        filter_term: {
                          attribute: "author",
                          value: [{ filter_value: "monalisa" }],
                          negative: nil,
                        }
                      },
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
          { filter_term: { negative: nil, attribute: "label", value: ["bug"] } },
          { text_term: "term_c" },
          { filter_term: { negative: nil, attribute: "author", value: ["monalisa"] } },
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
          explicit_operator: "OR",
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
          explicit_operator: "OR",
          right: {
            or: {
              left: { text_term: "term_b" },
              explicit_operator: "OR",
              right: {
                or: {
                  left: {
                    or: {
                      left: { text_term: "term_c" },
                      explicit_operator: "OR",
                      right: { text_term: "term_d" },
                    },
                  },
                  explicit_operator: "OR",
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
              explicit_operator: "AND",
              right: { text_term: "term_b" },
            }
          },
          explicit_operator: "OR",
          right: {
            and: {
              left: { text_term: "term_c" },
              right: {
                and: {
                  left: {
                    or: {
                      left: { text_term: "term_d" },
                      explicit_operator: "OR",
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
          { text_term: "term_a term_b" },
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
              explicit_operator: "AND",
              right: { quoted_text_term: { string: "double quoted" } },
            },
          },
          explicit_operator: "OR",
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
                      explicit_operator: "OR",
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
                      explicit_operator: "AND",
                      right: {
                        or: {
                          left: {
                            filter_term: {
                              negative: nil,
                              attribute: "created",
                              value: [{ filter_value: ">=@now-7d" }],
                            },
                          },
                          explicit_operator: "OR",
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
              { text_term: '"double quoted"' },
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
