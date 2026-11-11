# frozen_string_literal: true
require "test_helper"

class GraphQLProDeferTest < Minitest::Test
  parallelize_me!

  include Rack::Test::Methods
  include DeferHelpers

  class DeferSchema < GraphQL::Schema
    class NumberLoader < GraphQL::Batch::Loader
      def perform(numbers)
        numbers.each { |n| fulfill(n, numbers.size) }
      end
    end

    class Counter
      def initialize
        @count = 0
      end

      def increment(amount = 1 )
        @count += amount
      end
    end

    class IntegerList < GraphQL::Schema::Object
      field :ints, [Integer], null: false, resolve_static: true
      def self.ints(context)
        context[:counter] ||= Counter.new
        3.times.map {
          context[:counter].increment
        }
      end

      def ints
        self.class.ints(context)
      end

      field :batched_ints, [Integer], resolve_static: true
      def self.batched_ints(context)
        4.times.map { |n| NumberLoader.load(n) }
      end

      def batched_ints
        self.class.batched_ints(context)
      end

      field :int_list, IntegerList, null: false, resolve_static: true
      def self.int_list(context)
        :int_list
      end

      def int_list
        self.class.int_list(context)
      end

      field :execution_error, String, null: true, resolve_static: true
      def self.execution_error(context)
        raise GraphQL::ExecutionError, "Broke!"
      end

      def execution_error
        self.class.execution_error(context)
      end

      field :lazy_ints, [Integer], null: false, resolve_static: true
      def self.lazy_ints(context)
        context[:counter] ||= Counter.new
        GraphQL::Execution::Lazy.new {
          3.times.map {
            GraphQL::Execution::Lazy.new { context[:counter].increment }
          }
        }
      end

      def lazy_ints
        self.class.lazy_ints(context)
      end

      field :dataloaded_int, Integer, null: false, resolve_batch: true

      def self.dataloaded_int(objects, context)
        context.dataload_all(IntSource, context, objects.map { |_obj| SecureRandom.hex })
      end

      def dataloaded_int
        dataloader.with(IntSource, context).load(SecureRandom.hex)
      end

      field :dataloaded_ints, [Integer], null: false, resolve_static: true

      def self.dataloaded_ints(context)
        self.class.dataloaded_ints(context)
      end

      def dataloaded_ints
        self.class.dataloaded_ints(context)
      end

      def self.dataloaded_ints(context)
        source = context.dataloader.with(IntSource, context)
        r1 = source.request(SecureRandom.hex)
        r2 = source.request(SecureRandom.hex)
        r3 = source.request(SecureRandom.hex)
        [r1.load, r2.load, r3.load]
      end
    end

    class IntSource < GraphQL::Dataloader::Source
      def initialize(context)
        @context = context
      end

      def self.batch_key_for(_context)
        :shared
      end

      def fetch(random_keys)
        @context[:counter] ||= Counter.new

        v = @context[:counter].increment(random_keys.size)
        random_keys.map { |k| v }
      end
    end

    class Query < GraphQL::Schema::Object
      field :int, Integer, null: false, resolve_static: true
      def self.int(context)
        context[:counter] ||= Counter.new
        context[:counter].increment
      end

      def int
        self.class.int(context)
      end

      field :batched_int, Integer, resolve_static: true do
        argument :key, Integer, default_value: 0
      end

      def self.batched_int(context, key:)
        NumberLoader.load(key)
      end

      def batched_int(key:)
        self.class.batched_int(context, key: key)
      end

      field :int_list, IntegerList, null: false, resolve_static: true

      def self.int_list(context)
        GraphQL::Execution::Lazy.new { :int_list }
      end

      def int_list
        self.class.int_list(context)
      end

      field :batched_int_list, IntegerList, null: false, resolve_static: true
      def self.batched_int_list(context)
        NumberLoader.load(5) # just return a truthy promise
      end

      def batched_int_list
        self.class.batched_int_list(context)
      end

      field :multibyte_chars, String, null: false, resolve_static: true
      def self.multibyte_chars(context)
        "😈"
      end

      def multibyte_chars
        self.class.multibyte_chars(context)
      end
    end

    query(Query)

    class Defer < GraphQL::Pro::Defer
      def self.resolve(obj, arguments, context, &block)
        context[:graphql_batch_executor] ||= GraphQL::Batch::Executor.current
        super
      end

      class Deferral < GraphQL::Pro::Defer::Deferral
        def resolve
          prev_executor = GraphQL::Batch::Executor.current
          GraphQL::Batch::Executor.current ||= @context[:graphql_batch_executor]
          super
        ensure
          GraphQL::Batch::Executor.current = prev_executor
        end
      end
    end

    use Defer
    use GraphQL::Dataloader
    use GraphQL::Batch
  end

  def exec_query(...)
    if GRAPHQL_FUTURE
      DeferSchema.execute_next(...)
    else
      DeferSchema.execute(...)
    end
  end

  def test_it_defers_patches
    res = exec_query "{
      i1: int
      i2: int @defer
      i3: int @defer
    }"

    assert_equal({"i1" => 1}, res["data"], "The undeferred response")
    patches = get_patches(res)
    expected_patches = [
      {data: {"i1" => 1}, hasNext: true},
      {path: ["i2"], data: 2, hasNext: true},
      {path: ["i3"], data: 3, hasNext: false}
    ]
    assert_equal(expected_patches, patches, "each patch comes through")
    assert_equal({"i1" => 1, "i2" => 2,"i3" => 3 }, final_result(res, patches)["data"], "The final response")
  end

  def test_it_accepts_if
    res = exec_query "{
      i1: int
      i2: int @defer(if: false)
      i3: int @defer(if: true)
    }"

    assert_equal({"i1" => 1, "i2" => 2}, res["data"], "The undeferred response")

    patches = get_patches(res)
    expected_patches = [
      {data: {"i1" => 1, "i2" => 2}, hasNext: true},
      {path: ["i3"], data: 3, hasNext: false}
    ]
    assert_equal(expected_patches, patches)
  end

  def test_it_runs_nested_defers
    res = exec_query "{
      int
      intList @defer {
        intList @defer {
          ints @defer
        }
      }
    }"

    assert_equal({"int" => 1}, res["data"], "The undeferred response")

    patches = get_patches(res)
    expected_patches = [
      { data: { "int" => 1}, hasNext: true },
      { path: ["intList"], data: {}, hasNext: true },
      { path: ["intList", "intList"], data: {}, hasNext: true },
      { path: ["intList", "intList", "ints"], data: [2,3,4], hasNext: false },
    ]
    assert_equal(expected_patches, patches)
  end

  def test_it_defers_fragment_spreads
    res = exec_query "
    {
      i1: int
      ...QueryFragment @defer
    }

    fragment QueryFragment on Query {
      intList {
        i2: dataloadedInt
        i3: dataloadedInt
      }
    }"

    assert_equal({"i1" => 1}, res["data"], "The undeferred response")

    patches = get_patches(res)
    expected_patches = [
      { data: { "i1" => 1}, hasNext: true },
      { path: [], hasNext: false, data: { "intList" => { "i2" => 3, "i3" => 3 } } },
    ]
    assert_equal expected_patches, patches
  end

  class DeferBugSchema < GraphQL::Schema
    class Issue < GraphQL::Schema::Object
      field :title, String
      field :body, String
    end

    class Repo < GraphQL::Schema::Object
      field :issue, Issue
      field :name, String
    end

    class Query < GraphQL::Schema::Object
      field :repo, Repo, resolve_static: true

      def self.repo(context)
        {
          name: "my repo",
          issue: {
            title: "Failed Reticulated Splines",
            body: "It encountered an error while reticulating splines"
          }
        }
      end

      def repo
        self.class.repo(context)
      end
    end

    query(Query)
    use GraphQL::Pro::Defer
  end

  def test_it_defers_inline_fragments_in_fragment_definition
    res = DeferBugSchema.execute " {
      repo  {
        ...RepoFrag
      }
    }

    fragment RepoFrag on Repo {
      ... @defer {
        name
      }
    }"

    patches = get_patches(res)
    expected_patches = [
      {:hasNext=>true, :data=>{"repo"=>{}}},
      {:path=>["repo"], :hasNext=>false, :data=>{"name"=>"my repo"}}
    ]
    assert_equal expected_patches, patches
  end

  def test_it_defers_deeply_nested_fragments
    res = DeferBugSchema.execute " {
      repo  {
        ...RepoFrag
      }
    }

    fragment RepoFrag on Repo {
      name
      issue {
        ... IssueFrag
      }
    }

    fragment IssueFrag on Issue {
      title
      ... IssueBody @defer
    }

    fragment IssueBody on Issue {
      body
    }"

    first_res = {"repo"=>{"name"=>"my repo", "issue"=>{"title"=>"Failed Reticulated Splines"}}}
    assert_equal(first_res, res["data"], "The undeferred response")

    patches = get_patches(res)
    expected_patches = [
      {
        :hasNext=>true,
        :data=>{"repo"=>{"name"=>"my repo", "issue"=>{"title"=>"Failed Reticulated Splines"}}}
      },
      {
        :path=>["repo", "issue"],
        :hasNext=>false,
        :data=>{"body"=>"It encountered an error while reticulating splines"}
      }
    ]
    assert_equal expected_patches, patches
  end

  def test_it_defers_inside_fragments
    res = exec_query "
    {
      i1: int
      ...QueryFragment
    }

    fragment QueryFragment on Query {
      intList {
        i2: dataloadedInt @defer
        i3: dataloadedInt
      }
    }"

    assert_equal({"i1" => 1, "intList" => { "i3" => 2 }}, res["data"], "The undeferred response")

    patches = get_patches(res)
    expected_patches = [
      { data: { "i1" => 1, "intList" => { "i3" => 2 }}, hasNext: true },
      { path: ["intList", "i2"], hasNext: false, data: 3 },
    ]
    assert_equal expected_patches, patches
  end

  def test_it_defers_on_anonymous_fragments_inside_fragments
    res = exec_query "
    {
      i1: int
      ...QueryFragment
    }

    fragment QueryFragment on Query {
      intList {
        i2: dataloadedInt @defer
        i3: dataloadedInt
      }
    }"

    assert_equal({"i1" => 1, "intList" => { "i3" => 2 }}, res["data"], "The undeferred response")

    patches = get_patches(res)
    expected_patches = [
      { data: { "i1" => 1, "intList" => { "i3" => 2 }}, hasNext: true },
      { path: ["intList", "i2"], hasNext: false, data: 3 },
    ]
    assert_equal expected_patches, patches
  end

  def test_it_defers_inline_fragments
    res = exec_query "
    {
      i1: int
      ... @defer {
        i2: int
      }
    }"

    assert_equal({"i1" => 1}, res["data"], "The undeferred response")

    patches = get_patches(res)
    expected_patches = [
      { data: { "i1" => 1}, hasNext: true },
      { path: [], data: { "i2" => 2 }, hasNext: false },
    ]
    assert_equal expected_patches, patches
  end

  def test_it_defers_with_lazy
    res = exec_query "{
      intList @defer {
        lazyInts @defer
        intList {
          lazyInts @defer
        }
      }
    }", context: { counter: DeferSchema::Counter.new }

    patches = get_patches(res)
    expected_patches = [
      { data: {}, hasNext: true },
      { path: ["intList"], data: { "intList" => {} }, hasNext: true },
      { path: ["intList", "lazyInts"], data: [1,2,3], hasNext: true },
      { path: ["intList", "intList", "lazyInts"], data: [4,5,6], hasNext: false },
    ]
    assert_equal expected_patches, patches
  end

  def test_it_defers_errors
    res = exec_query "{
      int
      intList @defer {
        intList @defer {
          executionError @defer
        }
      }
    }"

    expected_patches = [
      { data: {"int" => 1 }, hasNext: true },
      { path: ["intList"], data: {}, hasNext: true },
      { path: ["intList", "intList"], data: {}, hasNext: true },
      {
        path: ["intList", "intList", "executionError"],
        errors: [{"message"=>"Broke!", "locations"=>[{"line"=>5, "column"=>11}], "path"=>["intList", "intList", "executionError"]}],
        hasNext: false,
      },
    ]

    patches = get_patches(res)
    assert_equal(expected_patches, patches, "patches contain errors")
  end

  def test_skip_takes_priority
    res = exec_query "{
      int @defer
      int2: int @defer @skip(if: true)
    }"

    assert_equal({}, res["data"], "The undeferred response")
    patches = get_patches(res)
    expected_patches = [
      {data: {}, hasNext: true},
      {path: ["int"], data: 1, hasNext: false},
    ]
    assert_equal(expected_patches, patches, "int2 is not present because it was skipped")
  end

  def test_it_adds_a_root_deferral
    res = exec_query "{
      int
      int2: int @defer
    }"
    deferrals = res.context[:defer].deferrals
    root_deferral = deferrals.first

    assert_instance_of GraphQL::Pro::Defer::RootDeferral, root_deferral
    assert_nil root_deferral.path
    assert_nil root_deferral.errors
    assert root_deferral.has_next?
    assert_equal({"int" => 1}, root_deferral.data)

    refute deferrals.last.has_next?
  end

  def test_it_includes_label_in_patches
    res = exec_query "{
      int
      int2: int @defer(label: \"int2-label\")
    }"

    patches = get_patches(res)
    expected_patches = [
      { data: { "int" => 1 }, hasNext: true },
      { path: ["int2"], data: 2, label: "int2-label", hasNext: false },
    ]
    assert_equal expected_patches, patches
  end

  def test_it_defers_fields_that_return_arrays
    res = exec_query "{
      intList {
        dataloadedInts @defer
       }
    }"

    patches = get_patches(res)
    expected_patches = [
      { data: { "intList" => {} }, hasNext: true },
      { path: ["intList", "dataloadedInts"], data: [3, 3, 3], hasNext: false },
    ]
    assert_equal expected_patches, patches
  end

  def test_it_creates_http_multipart
    res = exec_query "{
      multibyteChars
      intList @defer {
        ints
      }
    }"

    multiparts = res.context[:defer].map.with_index { |deferral, idx| deferral.to_http_multipart(first: idx == 0) }
    assert_equal 2, multiparts.size
    first_part, second_part = multiparts
    validate_multipart(first_part)
    assert_equal "\r\n---\r\nContent-Type: application/json\r\nContent-Length: 49\r\n\r\n{\"hasNext\":true,\"data\":{\"multibyteChars\":\"😈\"}}\r\n---", first_part
    validate_multipart(second_part)
    assert_equal "\r\nContent-Type: application/json\r\nContent-Length: 60\r\n\r\n{\"path\":[\"intList\"],\"hasNext\":false,\"data\":{\"ints\":[1,2,3]}}\r\n-----", second_part
  end

  def test_it_works_with_multiplex
    res = DeferSchema.multiplex([
      { query: "{ int int2: int @defer }" },
      { query: "{
        int
        intList @defer {
          intList @defer {
            executionError @defer
          }
        }
      }" },
      { query: "
      {
        i1: int
        ...QueryFragment @defer
      }

      fragment QueryFragment on Query {
        intList {
          i2: dataloadedInt
          i3: dataloadedInt
        }
      }", }
    ])

    expected_patches = [
      [
        { data: { "int" => 1 }, hasNext: true },
        { path: ["int2"], hasNext: false, data: 2}
      ],
      [
        { data: {"int" => 1 }, hasNext: true },
        { path: ["intList"], data: {}, hasNext: true },
        { path: ["intList", "intList"], data: {}, hasNext: true },
        {
          path: ["intList", "intList", "executionError"],
          errors: [{"message"=>"Broke!", "locations"=>[{"line"=>5, "column"=>13}], "path"=>["intList", "intList", "executionError"]}],
          hasNext: false,
        },
      ],
      [
        { data: { "i1" => 1}, hasNext: true },
        { path: [], hasNext: false, data: { "intList" => { "i2" => 3, "i3" => 3 } } },
      ]
    ]

    actual_patches = []
    res.each do |query_res|
      actual_patches << get_patches(query_res)
    end

    expected_patches.each_with_index do |expected, i|
      expected.each_with_index do |exp_patch, i2|
        assert_equal exp_patch, actual_patches[i][i2], "Patches for [#{i}, #{i2}] matched"
      end
    end
  end

  def test_it_streams_http_multipart
    res = exec_query "{
      int
      int2: int @defer
      int3: int @defer
    }"

    deferred = res.context[:defer]
    response = DummyResponse.new
    deferred.stream_http_multipart(response)
    expected_headers = { "Content-Type" => "multipart/mixed; boundary=\"-\"" }
    assert_equal(expected_headers, response.headers)
    assert_equal(3, response.patches.size)
    assert response.patches.last.end_with?("\r\n-----"), "It adds a terminator"
  end

  def test_it_works_with_defering_the_same_field_twice
    res = exec_query "{
      __typename @defer
      __typename @defer
    }"

    assert_equal({}, res["data"], "The undeferred response")
    patches = get_patches(res)
    expected_patches = [
      {data: {}, hasNext: true},
      {path: ["__typename"], data: "Query", hasNext: false},
    ]
    assert_equal(expected_patches, patches, "There's only one defered payload")


    res = exec_query "{
      __typename @defer
      __typename @defer
      __typename @defer
      __typename @defer
      __typename @defer
      __typename @defer
      t2: __typename @defer
    }"

    patches = get_patches(res)
    expected_patches = [
      {data: {}, hasNext: true},
      {path: ["__typename"], data: "Query", hasNext: true},
      {path: ["t2"], data: "Query", hasNext: false},
    ]
    assert_equal(expected_patches, patches, "Fields with different names are defered separately")
  end

  def test_it_streams_new_apollo_style
    res = exec_query "{
      int
      int2: int @defer
      int3: int @defer
    }"

    deferred = res.context[:defer]
    response = DummyResponse.new
    deferred.stream_http_multipart(response, incremental: true)
    expected_headers = { "Content-Type" => "multipart/mixed; boundary=\"-\"" }
    assert_equal(expected_headers, response.headers)
    assert_equal(3, response.patches.size)
    # The first patch has no `incremental:` array
    assert_includes response.patches[0], '{"hasNext":true,"data":{"int":1}}'
    # Later patches do
    assert_includes response.patches[1], '{"incremental":[{"path":["int2"],"data":2}],"hasNext":true}'
    assert_includes response.patches[2], '{"incremental":[{"path":["int3"],"data":3}],"hasNext":false}'
    assert response.patches.last.end_with?("\r\n-----"), "It adds a terminator"
  end

  def test_it_works_with_graphql_batch
    res = exec_query "{
      intList {
        intList {
          batchedInts
        }
      }
      int1: batchedInt
      int2: batchedInt @defer
      deferredList: batchedIntList @defer {
        intList @defer {
          batchedInts @defer
        }
      }
      int3: batchedInt(key: 2) @defer
    }", context: { backtrace: true }

    patches = get_patches(res)
    expected_patches = [
      {:hasNext=>true, :data=>{"intList"=>{"intList"=>{"batchedInts"=>[1, 3, 3, 3]}}, "int1"=>1}},
      {:path=>["deferredList"], :hasNext=>true, :data=>{}},
      {:path=>["int2"], :hasNext=>true, :data=>1},
      # This is the cached value from when `2` is in the list:
      {:path=>["int3"], :hasNext=>true, :data=>3},
      {:path=>["deferredList", "intList"], :hasNext=>true, :data=>{}},
      {:path=>["deferredList", "intList", "batchedInts"], :hasNext=>false, :data=>[1, 3, 3, 3]}
    ]

    if GRAPHQL_FUTURE
      a = expected_patches[1]
      b = expected_patches[2]
      expected_patches[2] = a
      expected_patches[1] = b
    end

    assert_equal(expected_patches, patches)

    res2 = exec_query "{
      deferredList: intList @defer {
        intList @defer {
          batchedInts @defer
        }
      }
      int4: batchedInt(key: 2) @defer
    }"
    patches = get_patches(res2)
    # `1` comes from `key: 2` which is evaluated first
    # then, 0, 2, and 3, which get `3` for a value since there were 3 in the list
    # This is to make sure that the GraphQL-Batch cache is shared between deferred resolutions
    expected_patches = [
      {:hasNext=>true, :data=>{}},
      {:path=>["deferredList"], :hasNext=>true, :data=>{}},
      {:path=>["int4"], :hasNext=>true, :data=>1},
      {:path=>["deferredList", "intList"], :hasNext=>true, :data=>{}},
      {:path=>["deferredList", "intList", "batchedInts"], :hasNext=>false, :data=>[3, 3, 1, 3]}
    ]
    assert_equal(expected_patches, patches)
  end

  # Rack::Test Setup
  def app
    builder = Rack::Builder.new
    builder.run DeferHelpers.create_streaming_sinatra_app(DeferSchema)
    builder
  end

  def test_it_runs_with_sinatra_streaming
    post "/graphql", {query: "{ i1: int i2: int @defer }"}
    expected_body = %|{"hasNext":true,"data":{"i1":1}}\n\n{"path":["i2"],"hasNext":false,"data":2}\n\n|
    assert_equal expected_body, last_response.body
  end
end
