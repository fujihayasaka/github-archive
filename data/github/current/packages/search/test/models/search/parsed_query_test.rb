# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchParsedQueryTest < GitHub::TestCase
  fixtures do
    @current_user = create :user
  end

  def assert_bool_collection(must: nil, must_not: nil, should: nil, and_should: nil, collection:)
    assert_instance_of Search::ParsedQuery::BoolCollection, collection
    if must.nil?
      assert_nil collection.must, "'must' clause is not nil"
    else
      assert_equal must,     collection.must,     "'must' clause disagrees"
    end
    if must_not.nil?
      assert_nil collection.must_not, "'must_not' clause disagrees"
    else
      assert_equal must_not, collection.must_not, "'must_not' clause disagrees"
    end
    if should.nil?
      assert_nil collection.should, "'should' clause is not nil"
    else
      assert_equal should,   collection.should,   "'should' clause disagrees"
    end
    if and_should.nil?
      assert_nil collection.and_should, "'and_should' clause is not nil"
    else
      assert_equal and_should, collection.and_should, "'and_should' clause disagrees"
    end
  end

  context "Parse syntax" do
    test "blank" do
      assert_equal [], Search::ParsedQuery.parse("")
    end

    test "without terms" do
      assert_equal ["bug"],
        Search::ParsedQuery.parse("bug")
      assert_equal ["bug"],
        Search::ParsedQuery.parse("  bug  ")
      assert_equal ["bug and more bugs"],
        Search::ParsedQuery.parse("bug and more bugs")
      assert_equal ["serious kind:bug"],
        Search::ParsedQuery.parse("serious kind:bug")
      assert_equal [":rainbow: :ice_skate: onboarding"],
        Search::ParsedQuery.parse(":rainbow: :ice_skate: onboarding")
    end

    test "with single term" do
      assert_equal [[:state, "open"], "bug"],
        Search::ParsedQuery.parse("state:open bug", terms: [:state])
      assert_equal ["kind:open bug"],
        Search::ParsedQuery.parse("kind:open bug", terms: [:state])
      assert_equal ["bug kind:open"],
        Search::ParsedQuery.parse("bug kind:open", terms: [:state])
      assert_equal ["bug kind:open"],
        Search::ParsedQuery.parse("bug kind:open", terms: [:state])
    end

    test "with single term without whitespaces" do
      assert_equal ["bugstate:open"],
      Search::ParsedQuery.parse("bugstate:open", terms: [:state])
    end

    test "with terms between query" do
      assert_equal [[:state, "open"], "bug"],
        Search::ParsedQuery.parse("state:open bug", terms: [:state])
      assert_equal ["bug", [:state, "open"]],
        Search::ParsedQuery.parse("bug state:open", terms: [:state])
      assert_equal ["bug", [:state, "open"], "important"],
        Search::ParsedQuery.parse("bug state:open important", terms: [:state])
    end

    test "with negative term" do
      assert_equal [[:label, "bug"]],
        Search::ParsedQuery.parse("label:bug", terms: [:label])
      assert_equal [[:label, "bug", true]],
        Search::ParsedQuery.parse("-label:bug", terms: [:label])
    end

    test "with multiple terms" do
      assert_equal [[:state, "open"], [:type, "issue"]],
        Search::ParsedQuery.parse("state:open type:issue", terms: [:state, :type])
      assert_equal [[:state, "closed"], [:type, "issue"]],
        Search::ParsedQuery.parse("state:closed type:issue", terms: [:state, :type])
    end

    test "with quoted term" do
      assert_equal [[:state, "open"], [:label, "bug"], [:label, "issues"]],
        Search::ParsedQuery.parse("state:open label:bug label:issues", terms: [:state, :label])
      assert_equal [[:state, "open"], [:label, %Q{progressive enhancement}]],
        Search::ParsedQuery.parse(%Q{state:open label:"progressive enhancement"}, terms: [:state, :label])
      assert_equal [[:state, "open"], [:label, %Q{"progressive enhancement"}]],
        Search::ParsedQuery.parse(%Q{state:open label:"progressive enhancement"}, terms: [:state, :label], normalize_quotes: false)
      assert_equal [[:state, "open"], [:label, '"bugs"']],
        Search::ParsedQuery.parse('state:open label:"\"bugs\""', terms: [:state, :label])
      assert_equal [[:label, 'fix all the "bugs"']],
        Search::ParsedQuery.parse('label:"fix all the \"bugs\""', terms: [:label])
    end

    test "with comma-separated term, behavior differs based on the enumerable_terms passed in" do
      assert_equal [[:state, "open"], [:label, %w[bug feature]], [:label, "issues"]],
        Search::ParsedQuery.parse("state:open label:bug,feature label:issues", terms: [:state, :label], enumerable_terms: [:label])

      assert_equal [[:state, "open"], [:label, "bug,feature"], [:label, "issues"]],
        Search::ParsedQuery.parse("state:open label:bug,feature label:issues", terms: [:state, :label])
    end

    test "with comma-separated negative term, behavior differs based on the enumerable_terms passed in" do
      assert_equal [[:state, "open"], [:label, %w[bug feature], true], [:label, "issues"]],
        Search::ParsedQuery.parse("state:open -label:bug,feature label:issues", terms: [:state, :label], enumerable_terms: [:label])

      assert_equal [[:state, "open"], [:label, "bug,feature", true], [:label, "issues"]],
        Search::ParsedQuery.parse("state:open -label:bug,feature label:issues", terms: [:state, :label])
    end

    test "with comma separated quoted term" do
      assert_equal [[:state, "open"], [:label, ["bug", "feature flag"]], [:label, "issues"]],
        Search::ParsedQuery.parse("state:open label:\"bug\",\"feature flag\" label:issues", terms: [:state, :label], enumerable_terms: [:label])

      assert_equal [[:is, "issue"], [:label, ["good first issue", "bug"]]],
        Search::ParsedQuery.parse('is:issue label:"good first issue",bug', terms: [:is, :label], enumerable_terms: [:label])

      assert_equal [[:state, "open"], [:label, ["bug", "feature flag"]], [:label, "issues"]],
        Search::ParsedQuery.parse("state:open label:bug,\"feature flag\" label:issues", terms: [:state, :label], enumerable_terms: [:label])
    end

    test "with props syntax (regex)" do
      assert_equal [[:"props.sky", "blue"]],
        Search::ParsedQuery.parse("props.sky:blue", terms: ["props\\.\\w+"])

      assert_equal [[:"props.sky", "blue"], [:"props.field", %w[green yellow]]],
        Search::ParsedQuery.parse("props.sky:blue props.field:green,yellow", terms: ["props\\.\\w+"], enumerable_terms: ["props\\.\\w+"])
    end

    test "with @user syntax" do
      assert_equal ["@github"],
        Search::ParsedQuery.parse("@github")
      assert_equal [[:user, "github"]],
        Search::ParsedQuery.parse("@github", terms: [:user])
      assert_equal [[:user, "github", true]],
        Search::ParsedQuery.parse("-@github", terms: [:user])
      assert_equal ["repos", [:user, "github"]],
        Search::ParsedQuery.parse("repos @github", terms: [:user])
    end

    test "with @user/repo syntax" do
      assert_equal ["@github/github"],
        Search::ParsedQuery.parse("@github/github")
      assert_equal [[:repo, "github/github"]],
        Search::ParsedQuery.parse("@github/github", terms: [:repo])
      assert_equal [[:repo, "github/github", true]],
        Search::ParsedQuery.parse("-@github/github", terms: [:repo])
      assert_equal ["repos", [:repo, "github/github"]],
        Search::ParsedQuery.parse("repos @github/github", terms: [:repo])
    end

    test "with #topic syntax" do
      assert_equal ["#electron"],
        Search::ParsedQuery.parse("#electron"),
        "should be a no-op without the topic qualifier"

      assert_equal [[:topic, "electron"]],
        Search::ParsedQuery.parse("#electron", terms: [:topic])

      assert_equal [[:topic, "electron", true]],
        Search::ParsedQuery.parse("-#electron", terms: [:topic]),
        "expected the absence of the topic"

      assert_equal ["plugins", [:topic, "electron"]],
        Search::ParsedQuery.parse("plugins #electron", terms: [:topic])
    end

    if GitHub.enterprise?
      test "with environment syntax" do
        assert_equal [[:environment, "github"], "hodor"], Search::ParsedQuery.parse("environment:github hodor", terms: [:environment])
      end
    end
  end

  context "Stringify parsed query" do
    test "simple" do
      assert_equal "bug",
        Search::ParsedQuery.stringify(["bug"])
    end

    test "colon-style emoji" do
      assert_equal ":rainbow: :ice_skate: onboarding",
        Search::ParsedQuery.stringify([":rainbow: :ice_skate: onboarding"])
    end

    test "terms" do
      assert_equal "bug state:open",
        Search::ParsedQuery.stringify(["bug", [:state, "open"]])
      assert_equal "state:open bug",
        Search::ParsedQuery.stringify([[:state, "open"], "bug"])
    end

    test "multiple terms" do
      assert_equal "state:open label:bug label:issues",
        Search::ParsedQuery.stringify([[:state, "open"], [:label, "bug"], [:label, "issues"]])
    end

    test "enumerated terms" do
      assert_equal "state:open label:bug label:issues,features",
        Search::ParsedQuery.stringify([[:state, "open"], [:label, "bug"], [:label, %w[issues features]]])
      assert_equal 'label:bug,"good for new contributors"',
        Search::ParsedQuery.stringify([[:label, ["bug", "good for new contributors"]]])
    end

    test "quoted term" do
      assert_equal "state:open label:\"progressive enhancement\"",
        Search::ParsedQuery.stringify([[:state, "open"], [:label, "progressive enhancement"]])
      assert_equal 'state:open label:"\"bugs\""',
        Search::ParsedQuery.stringify([[:state, "open"], [:label, '"bugs"']])
      assert_equal 'state:open label:\bug/',
        Search::ParsedQuery.stringify([[:state, "open"], [:label, '\bug/']])
    end

    test "negative term" do
      assert_equal "state:open -label:bug",
        Search::ParsedQuery.stringify([[:state, "open"], [:label, "bug", true]])

      assert_equal "state:open -label:bug,feature",
        Search::ParsedQuery.stringify([[:state, "open"], [:label, %w[bug feature], true]])
    end

    test "non-ascii encodings" do
      assert_equal "label:☃",
        Search::ParsedQuery.stringify([[:label, "☃"]])
      assert_equal 'label:"☃ bugs"',
        Search::ParsedQuery.stringify([[:label, "☃ bugs"]])
    end
  end

  context "Parse/Stringify" do
    test "lossless" do
      qs = [
        "bug",
        "bug state:open",
        "state:open bug",
        "state:open foo:bar baz",
        "baz state:open foo:bar",
        "state:open foo:bar baz",
        'state:open label:"fix all the things" label:bug',
        'state:open label:"fix all the \"bugs\"" label:bug',
        'state:open label:"fix all the \"things\" and maybe some \"bugs\" if we have time" label:bug',
        "state:open -label:bug",
        'label:\bug/',
        "☃",
        "label:☃",
        'label:"☃ bugs"',
        "is:issue is:open sort:reactions-+1-desc",
      ]

      qs.each do |expected|
        ary = Search::ParsedQuery.parse(expected, terms: [:state, :label])
        str = Search::ParsedQuery.stringify(ary)
        assert_equal expected, str
      end
    end

    test "regular expression special characters are escaped" do
      terms      = ["foo)", :"(bar"]
      expression = "foo):foo-val (bar:bar-val"

      assert_nothing_raised do
        Search::ParsedQuery.parse(expression, terms: terms, escape_terms: true)
      end

      actual   = Search::ParsedQuery.parse(expression, terms: terms, escape_terms: true)
      expected = [[:"foo)", "foo-val"], [:"(bar", "bar-val"]]

      assert_equal expected, actual
    end

    test "query extra whitespace is stripped" do
      input  = "  bug  state:open  "
      output = "bug state:open"

      ary = Search::ParsedQuery.parse(input, terms: [:state])
      str = Search::ParsedQuery.stringify(ary)
      assert_equal output, str
    end

    test "colon-style emoji is not escaped" do
      input = ":rainbow: :ice_skate: onboarding"

      ary = Search::ParsedQuery.parse(input, terms: [:name, :sort])
      str = Search::ParsedQuery.stringify(ary)

      assert_equal input, str
    end

    test "unneeded quoting is stripped" do
      input  = "bug state:\"open\""
      output = "bug state:open"

      ary = Search::ParsedQuery.parse(input, terms: [:state])
      str = Search::ParsedQuery.stringify(ary)
      assert_equal output, str
    end

    test "legacy @user is normalized" do
      input  = "bug @TwP"
      output = "bug user:TwP"

      ary = Search::ParsedQuery.parse(input, terms: [:user])
      str = Search::ParsedQuery.stringify(ary)
      assert_equal output, str
    end

    test "legacy @user/repo is normalized" do
      input  = "bug @github/github"
      output = "bug repo:github/github"

      ary = Search::ParsedQuery.parse(input, terms: [:repo])
      str = Search::ParsedQuery.stringify(ary)
      assert_equal output, str
    end
  end

  context "Parsing phrases" do
    test "empty search phrase" do
      pq = Search::ParsedQuery.new nil

      assert_equal("", pq.phrase)
      assert_equal([], pq.terms)
      assert_equal("", pq.query)
      assert_equal({}, pq.qualifiers)
    end

    test "unmatched quotes" do
      text = '"chart library'
      pq = Search::ParsedQuery.new text
      assert_equal text, pq.query
      assert pq.qualifiers.empty?, "qualifiers should be empty"
    end

    test "simple search phrase" do
      text = "sample text"
      pq = Search::ParsedQuery.new text

      assert_equal text, pq.query
      assert pq.qualifiers.empty?, "qualifiers should be empty"
    end

    test "sanitize non UTF-8 characters" do
      naughty = "windows\xC0\xAFwin.ini"
      pq = Search::ParsedQuery.new naughty

      assert_equal "windows��win.ini", pq.query
      assert pq.qualifiers.empty?, "qualifiers should be empty"
    end

    test "colon-style emoji is not escaped" do
      input = ":rainbow: :ice_skate: onboarding"
      pq = Search::ParsedQuery.new(input)

      assert_equal ":rainbow: :ice_skate: onboarding", pq.query
      assert_predicate pq.qualifiers, :empty?
    end
  end

  context "Parsing with terms and qualifiers" do
    test "with terms" do
      text = "sample text"
      pq = Search::ParsedQuery.new(text, [:followers])

      refute_same text, pq.query
      assert_equal text, pq.query
      assert_equal [:followers], pq.terms
      assert pq.qualifiers.empty?, "qualifiers should be empty"
    end

    test "search phrase with qualifiers" do
      pq = Search::ParsedQuery.new("Chris followers:75", [:followers])
      assert_equal "Chris", pq.query
      assert_bool_collection(must: %w[75], collection: pq.qualifiers[:followers])

      pq = Search::ParsedQuery.new("require 'bundler' fork:false language:ruby", [:fork, :language])
      assert_equal "require 'bundler'", pq.query
      assert_bool_collection(must: %w[false], collection: pq.qualifiers[:fork])
      assert_bool_collection(must: %w[ruby], must_not:  nil, collection: pq.qualifiers[:language])

      pq = Search::ParsedQuery.new("literal query \"repos:44\" language:java", [:repos, :language])
      assert_equal 'literal query "repos:44"', pq.query
      assert_bool_collection(must: %w[java], collection: pq.qualifiers[:language])
      assert !pq.qualifiers.key?(:repos), ":repos should not be a qualifier"

      pq = Search::ParsedQuery.new("silly forks:42 query language:c++ but it repos:1 works", [:forks, :repos, :language])
      assert_equal "silly query but it works", pq.query
      assert_bool_collection(must: %w[42], collection: pq.qualifiers[:forks])
      assert_bool_collection(must: %w[1], collection: pq.qualifiers[:repos])
      assert_bool_collection(must: %w[c++], collection: pq.qualifiers[:language])
    end

    test "range qualifiers" do
      pq = Search::ParsedQuery.new("range query followers:25..50 language:java", [:followers, :language])
      assert_equal "range query", pq.query
      assert_bool_collection(must: %w[25..50], collection: pq.qualifiers[:followers])
      assert_bool_collection(must: %w[java], collection: pq.qualifiers[:language])

      pq = Search::ParsedQuery.new("forks:>10 language:ruby", [:forks, :language])
      assert_equal "", pq.query
      assert_bool_collection(must: %w[>10], collection: pq.qualifiers[:forks])
      assert_bool_collection(must: %w[ruby], collection: pq.qualifiers[:language])
    end

    test "search phrase with quotes" do
      pq = Search::ParsedQuery.new('""', [:noop])
      assert_equal'""', pq.query
      assert pq.qualifiers.empty?, "qualifiers should be empty"

      pq = Search::ParsedQuery.new('foo "" bar', [:noop])
      assert_equal('foo "" bar', pq.query)
      assert pq.qualifiers.empty?, "qualifiers should be empty"

      pq = Search::ParsedQuery.new("\"foo \\\"the bar\\\"\"", [:noop])
      assert_equal('"foo \\"the bar\\""', pq.query)
      assert pq.qualifiers.empty?, "qualifiers should be empty"

      pq = Search::ParsedQuery.new('\\"\\"', [:noop])
      assert_equal('\\"\\"', pq.query)
      assert pq.qualifiers.empty?, "qualifiers should be empty"

      pq = Search::ParsedQuery.new('\\" noop:42 \\"', [:noop])
      assert_equal('\\" \\"', pq.query)
      assert_bool_collection(must: %w[42], collection: pq.qualifiers[:noop])
    end

    test "search phrase with quoted fields" do
      pq = Search::ParsedQuery.new("templates language:C++", [:language])
      assert_equal "templates", pq.query
      assert_bool_collection(must: %w[C++], collection: pq.qualifiers[:language])

      pq = Search::ParsedQuery.new('templates language:"C++"', [:language])
      assert_equal "templates", pq.query
      assert_bool_collection(must: %w[C++], collection: pq.qualifiers[:language])

      pq = Search::ParsedQuery.new('templates language:"Emacs Lisp"', [:language])
      assert_equal "templates", pq.query
      assert_bool_collection(must: ["Emacs Lisp"], collection: pq.qualifiers[:language])

      pq = Search::ParsedQuery.new('templates language:"Emacs Lisp', [:language])
      assert_equal "templates Lisp", pq.query
      assert_bool_collection(must: %w["Emacs], collection: pq.qualifiers[:language])
    end

    test "search phrase with multiple qualifier terms" do
      pq = Search::ParsedQuery.new('location:"Boulder, CO" location:Boulder', [:location])
      assert_equal "", pq.query
      assert_bool_collection must: ["Boulder, CO", "Boulder"], collection: pq.qualifiers[:location]

      pq = Search::ParsedQuery.new('foo language:C++ language:Ruby language:Python language:"Emacs Lisp"', [:language])
      assert_equal "foo", pq.query
      assert_bool_collection must: ["C++", "Ruby", "Python", "Emacs Lisp"], collection: pq.qualifiers[:language]
    end

    test "search phrase with delimited qualifiers go into the and_should of the collection" do
      pq = Search::ParsedQuery.new("location:here,there", [:location], nil, [:location])
      assert_equal "", pq.query
      assert_bool_collection(and_should: [%w[here there]], collection: pq.qualifiers[:location])

      pq = Search::ParsedQuery.new("location:here,there location:anywhere", [:location], nil, [:location])
      assert_equal "", pq.query
      assert_bool_collection(must: ["anywhere"], and_should: [%w[here there]], collection: pq.qualifiers[:location])

      pq = Search::ParsedQuery.new("location:here,there location:anywhere location:up,down", [:location], nil, [:location])
      assert_equal "", pq.query
      assert_bool_collection(must: ["anywhere"], and_should: [%w[here there], %w[up down]], collection: pq.qualifiers[:location])

      # If :location isn't passed in as an enumerable term we put everything into the 'must'
      pq = Search::ParsedQuery.new("location:here,there location:anywhere location:up,down", [:location], nil, [])
      assert_equal "", pq.query
      assert_bool_collection(must: ["here,there", "anywhere", "up,down"],  collection: pq.qualifiers[:location])
    end

    test "negative qualifiers" do
      pq = Search::ParsedQuery.new("to_s -path:vendor/", [:fork, :language, :path])
      assert_equal "to_s", pq.query
      assert_bool_collection(must_not: %w[vendor/], collection: pq.qualifiers[:path])

      pq = Search::ParsedQuery.new("to_s -path:vendor/ -path:test/ -path:spec/", [:path])
      assert_equal "to_s", pq.query
      assert_bool_collection(must_not: %w[vendor/ test/ spec/], collection: pq.qualifiers[:path])

      pq = Search::ParsedQuery.new("-location:here,there location:anywhere", [:location], nil, [:location])
      assert_equal "", pq.query
      assert_bool_collection(must: ["anywhere"], must_not: %w[here there], collection: pq.qualifiers[:location])

      # negative qualifiers still get parsed into a single must_not if :location isn't passed in as an
      # enumerable_term
      pq = Search::ParsedQuery.new("-location:here,there location:anywhere", [:location])
      assert_equal "", pq.query
      assert_bool_collection(must: ["anywhere"], must_not: ["here,there"], collection: pq.qualifiers[:location])

      # The kitchen sink
      pq = Search::ParsedQuery.new("-location:here,there -location:foo -location:above,below  location:anywhere location:up,down", [:location], nil, [:location])
      assert_equal "", pq.query
      assert_bool_collection(must: ["anywhere"], must_not: %w[here there foo above below], and_should: [%w[up down]], collection: pq.qualifiers[:location])
    end

    test "@user filter" do
      pq = Search::ParsedQuery.new("to_s @github")
      assert_equal "to_s", pq.query
      assert_bool_collection(must: %w[github], collection: pq.qualifiers[:user])

      pq = Search::ParsedQuery.new("to_s @github language:ruby", [:language])
      assert_equal "to_s", pq.query
      assert_bool_collection(must: %w[github], collection: pq.qualifiers[:user])
      assert_bool_collection(must: %w[ruby], collection: pq.qualifiers[:language])

      pq = Search::ParsedQuery.new("to_s @github to_a")
      assert_equal "to_s to_a", pq.query
      assert_bool_collection(must: %w[github], collection: pq.qualifiers[:user])
    end

    test "@user/repo filter" do
      pq = Search::ParsedQuery.new("to_s @github/github")
      assert_equal "to_s", pq.query
      assert_bool_collection(must: %w[github/github], collection: pq.qualifiers[:repo])

      pq = Search::ParsedQuery.new("to_s @github/github language:coffeescript", [:language])
      assert_equal "to_s", pq.query
      assert_bool_collection(must: %w[github/github], collection: pq.qualifiers[:repo])
      assert_bool_collection(must: %w[coffeescript], collection: pq.qualifiers[:language])

      pq = Search::ParsedQuery.new("to_s @github/github to_a")
      assert_equal "to_s to_a", pq.query
      assert_bool_collection(must: %w[github/github], collection: pq.qualifiers[:repo])

      pq = Search::ParsedQuery.new("to_s @github/github/error")
      assert_equal "to_s @github/github/error", pq.query
      assert pq.qualifiers.empty?, "qualifiers should be empty"

      pq = Search::ParsedQuery.new("rock @github/hubot-classic -@github/github")
      assert_equal "rock", pq.query
      assert_bool_collection(must: %w[github/hubot-classic], must_not: %w[github/github], collection: pq.qualifiers[:repo])

      pq = Search::ParsedQuery.new("rock @plone/foo.bar_baz-buz")
      assert_equal "rock", pq.query
      assert_bool_collection(must: %w[plone/foo.bar_baz-buz], collection: pq.qualifiers[:repo])
    end

    if GitHub.enterprise?
      test "environment filter" do
        pq = Search::ParsedQuery.new("environment:github hodor", [:environment])
        assert_equal "github", T.unsafe(pq).environment
        assert_equal "hodor", pq.query
        assert_empty pq.qualifiers
      end
    end
  end

  context "BoolCollection functionality" do
    setup do # rubocop:disable GitHub/NestedSetupTeardown
      @bc = Search::ParsedQuery::BoolCollection.new :foo
      @bc.must "one"
      @bc.must_not "two"
      @bc.must "three"
      @bc.should "four"
      @bc.and_should %w[five six]
    end

    test "duplication" do
      copy = @bc.dup
      @bc.must_not "five"

      refute_equal @bc.object_id, copy.object_id
      assert_equal :foo, copy.name
      assert_bool_collection(must: %w[one three], must_not: %w[two], should: %w[four], and_should: [%w[five six]], collection: copy)
    end

    test "uniqueness" do
      @bc.must "one"
      assert_equal %w[one three one], @bc.must

      @bc.uniq!
      assert_equal %w[one three], @bc.must

      @bc.must %w[three four five]
      @bc.must_not %w[two three four]
      @bc.should %w[four five six]
      @bc.and_should %w[five six]
      @bc.uniq!

      assert_equal %w[one three four five], @bc.must
      assert_equal %w[two three four],      @bc.must_not
      assert_equal %w[four five six],       @bc.should
      assert_equal [%w[five six]],       @bc.and_should

      bc = Search::ParsedQuery::BoolCollection.new :bar
      bc.must %w[one two two three]
      bc.uniq!

      assert_equal %w[one two three], bc.must
      assert_nil bc.must_not
      assert_nil bc.should
    end

    test "merging in situ" do
      other = Search::ParsedQuery::BoolCollection.new
      other.must "pi"
      other.must_not "tau"

      @bc.merge! other
      assert_bool_collection(must: %w[one three pi], must_not: %w[two tau], should: %w[four], and_should: [%w[five six]], collection: @bc)
      assert_bool_collection(must: %w[pi], must_not: %w[tau], collection: other)

      another = Search::ParsedQuery::BoolCollection.new
      another.must "e"
      another.merge! other
      another.must_not "epsilon"

      assert_bool_collection(must: %w[e pi], must_not: %w[tau epsilon], collection: another)
      assert_bool_collection(must: %w[pi], must_not: %w[tau], collection: other)
      assert_bool_collection(must: %w[one three pi], must_not: %w[two tau], should: %w[four], and_should: [%w[five six]], collection: @bc)
    end

    test "merging" do
      other = Search::ParsedQuery::BoolCollection.new
      other.must "pi"
      other.must_not "tau"
      other.and_should(%w[a b])

      copy = @bc.merge other
      copy.should "epsilon"
      other.must "delta"

      assert_bool_collection(must: %w[one three], must_not: %w[two], should: %w[four], and_should: [%w[five six]], collection: @bc)
      assert_bool_collection(must: %w[one three pi], must_not: %w[two tau], should: %w[four epsilon], and_should: [%w[five six], %w[a b]], collection: copy)
      assert_bool_collection(must: %w[pi delta], must_not: %w[tau], and_should: [%w[a b]], collection: other)
    end

    test "equality" do
      other = Search::ParsedQuery::BoolCollection.new :foo
      refute_equal @bc, other

      other.must "one"
      other.must_not "two"
      other.should "four"
      refute_equal @bc, other

      other.must "three"
      other.and_should %w[five six]
      assert_equal @bc, other
    end

    test "raises type errors" do
      assert_raises(TypeError) { @bc.merge "foo" }
      assert_raises(TypeError) { @bc.merge! "foo" }
    end

    test "all components" do
      assert_equal %w[one three two four five six], @bc.all
    end

    test "mapping all values" do
      assert_equal %w[one three two four five six], @bc.all

      @bc.map_all! { |value| value.upcase }
      assert_equal [%w[FIVE SIX]], @bc.and_should
      assert_equal %w[ONE THREE TWO FOUR FIVE SIX], @bc.all
    end

    test "flatmapping all values" do
      assert_equal %w[one three two four five six], @bc.all

      @bc.flatmap_all! do |value|
        case value
        when "one"
          []
        when "three"
          ["3.0", "3.1", "3.2"]
        when "two"
          %w[TWO 2]
        else
          [value]
        end
      end

      assert_equal %w[3.0 3.1 3.2 TWO 2 four five six], @bc.all
    end

    test "intersecting components" do
      @bc.must_not "one"
      @bc.must_not "four"
      @bc.must_not "five"
      assert_equal %w[one three two one four five four five six], @bc.all

      @bc.intersect!

      assert_equal %w[three], @bc.must
      assert_equal %w[two one four five], @bc.must_not
      assert_equal %w[], @bc.should
      assert_equal [%w[six]], @bc.and_should
      assert_equal %w[three two one four five six], @bc.all
    end

    test "empty collection detection" do
      bc = Search::ParsedQuery::BoolCollection.new
      assert bc.blank?, "collection should be empty"

      bc.must "foo"
      assert !bc.blank?, "collection is not blank"

      bc.clear
      assert bc.blank?, "collection should be empty"

      bc.must_not "foo"
      assert !bc.blank?, "collection is not blank"

      bc.clear
      assert bc.blank?, "collection should be empty"

      bc.should "foo"
      assert !bc.blank?, "collection is not blank"

      bc.clear
      bc.and_should %w[foo bar]
      assert !bc.blank?, "collection is not blank"
    end
  end

  context "macro substitution" do
    test "@me is replaced with current user login when replace_me is true" do
      parsed_query        = Search::ParsedQuery.parse("assignee:@me", terms: ["assignee"], viewer: @current_user, enumerable_terms: ["assignee"], replace_me: true)
      actual_parsed_value = parsed_query.first.last # the last element in the first nested array.

      assert_equal @current_user.login, actual_parsed_value
    end

    test "@me is not replaced with current user login by default" do
      parsed_query        = Search::ParsedQuery.parse("assignee:@me", terms: ["assignee"], viewer: @current_user, enumerable_terms: ["assignee"])
      actual_parsed_value = parsed_query.first.last # the last element in the first nested array.

      assert_equal "@me", actual_parsed_value
    end
  end

  context "#apply_me_macro" do
    test "replaces @me with current user login for all Search::Query::USERNAME_SEARCH_FIELDS" do
      Search::Query::USERNAME_SEARCH_FIELDS.each do |field|
        actual = Search::ParsedQuery.apply_me_macro(@current_user, field, "@me")

        assert_equal @current_user.login, actual
      end
    end

    test "accepts and returns nested arrays as a value" do
      actual   = Search::ParsedQuery.apply_me_macro(@current_user, :assignee, ["@me", ["@me"], [["@me"]]])
      expected = [@current_user.login, [@current_user.login], [[@current_user.login]]]

      assert_equal expected, actual
    end

    test "array depth recursion is bound and does not go past 5 levels deep" do
      inner_array = T.let(["6", "@me"], Array)
      infinite_loop = T.let(["1", "@me", ["2", "@me", ["3", "@me", ["4", "@me", ["5", "@me", inner_array]]]]], Array)
      inner_array << infinite_loop # create a circular reference

      actual = Search::ParsedQuery.apply_me_macro(@current_user, :assignee, infinite_loop)

      (1..6).map(&:to_s).each do |index|
        # max recursion depth is 5, so 6th instance should not be replaced with the login
        expected_value = index == "6" ? "@me" : @current_user.login

        assert_equal index, actual[0]
        assert_equal expected_value, actual[1]

        # for the next iteration
        actual = actual[2] if actual[2]
      end
    end
  end
end
