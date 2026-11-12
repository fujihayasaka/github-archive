# frozen_string_literal: true

GraphQL::Pro::FutureStream.hide_deprecation_warning
module StreamAssertions
  include DeferHelpers

  class Counter
    def initialize
      @value = 0
    end

    def increment(amount = 1)
      @value += amount
    end
  end

  class StreamSchema < GraphQL::Schema
    class IntegerList < GraphQL::Schema::Object
      class StreamableField < GraphQL::Schema::Field
        def initialize(*args, streamable: nil, **kwargs, &block)
          super(*args, **kwargs, &block)
          if streamable == true ||
              (streamable.nil? && (type.list? || (type.non_null? && type.of_type.list?)))
            extension(GraphQL::Pro::FutureStream::StreamableExtension)
          end
        end
      end

      field_class(StreamableField)

      field :ints, [Integer], null: false, resolve_each: true
      def self.ints(object, context)
        context[:counter] ||= Counter.new
        Enumerator.new(3) do |y|
          3.times do
            y.yield(context[:counter].increment)
          end
        end
      end

      def ints
        self.class.ints(object, context)
      end

      field :int_list, IntegerList, null: false, resolve_static: true
      def self.int_list(context)
        :int_list
      end

      def int_list
        self.class.int_list(context)
      end

      field :int_lists, [IntegerList], null: false, resolve_static: true
      def self.int_lists(context)
        context.streamable([:int_list, :int_list])
      end

      def int_lists
        self.class.int_lists(context)
      end

      field :execution_errors, [String], null: true, resolve_static: true
      def self.execution_errors(context)
        [GraphQL::ExecutionError.new("Broke!")]
      end

      def execution_errors
        self.class.execution_errors(context)
      end

      field :lazy_ints, [Integer], null: false, resolve_static: true
      def self.lazy_ints(context)
        context[:counter] ||= Counter.new
        GraphQL::Execution::Lazy.new {
          3.times.lazy.map { |i|
            GraphQL::Execution::Lazy.new { context[:counter].increment }
          }
        }
      end

      def lazy_ints
        self.class.lazy_ints(context)
      end

      field :dataloaded_ints, [Integer], null: false, resolve_static: true

      def self.dataloaded_ints(context)
        r1 = context.dataloader.with(IntSource, context).request(SecureRandom.hex)
        r2 = context.dataloader.with(IntSource, context).request(SecureRandom.hex)
        r3 = context.dataloader.with(IntSource, context).request(SecureRandom.hex)
        requests = [r1, r2, r3]
        Enumerator.new(3) do |y|
          3.times do |i|
            y << requests[i].load
          end
        end
      end

      def dataloaded_ints
        self.class.dataloaded_ints(context)
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

    class IntListLoader < GraphQL::Batch::Loader
      def perform(ids)
        ids.each { |id| fulfill(id, [id, id + 1, id + 2]) }
      end
    end

    class Query < GraphQL::Schema::Object
      field :int, Integer, resolve_static: true
      def self.int(context)
        context[:counter] ||= Counter.new
        context[:counter].increment
      end

      def int
        self.class.int(context)
      end

      field :int_list, IntegerList, resolve_static: true
      def self.int_list(context)
        GraphQL::Execution::Lazy.new { :int_list }
      end

      def int_list
        self.class.int_list(context)
      end

      field :int_lists, [IntegerList], streamable: true, resolve_static: true
      def self.int_lists(context)
        [
          GraphQL::Execution::Lazy.new { :int_list },
          GraphQL::Execution::Lazy.new { :int_list },
        ]
      end

      def int_lists
        self.class.int_lists(context)
      end

      field :batched_ints, [Integer], streamable: true, resolve_static: true
      def self.batched_ints(context)
        IntListLoader.load(1)
      end

      def batched_ints
        self.class.batched_ints(context)
      end

      field :multibyte_chars, [String], null: false, streamable: true, resolve_static: true
      def self.multibyte_chars(context)
        ["😈"]
      end

      def multibyte_chars
        self.class.multibyte_chars(context)
      end

      field :ints, [Integer], null: false, streamable: true, resolve_static: true
      def self.ints(context)
        context[:counter] ||= Counter.new
        Enumerator.new(3) do |y|
          3.times do
            y.yield(context[:counter].increment)
          end
        end
      end

      def ints
        self.class.ints(context)
      end

      field :error_enumerator, [Int], streamable: true, resolve_static: true
      def self.error_enumerator(context)
        Enumerator.new(context[:enumerator_size] == false ? nil : 3) do |y|
          y << 1
          y << 2
          raise context[:error_class].new("Boom!#{context[:enumerator_size] == false ? " (peek)" : ""}")
          y << 3
        end
      end

      def error_enumerator
        self.class.error_enumerator(context)
      end
    end

    query(Query)
    mutation(Query)
    use GraphQL::Dataloader
    use GraphQL::Batch
    module StreamTrace
      def execute_multiplex(multiplex:)
        multiplex.queries.each { |q| q.context[:was_traced] = q.object_id }
        super
      end
    end

    trace_with(StreamTrace)

    def self.resolve_type(type, obj, ctx)
      type
    end
  end

  def exec_query(...)
    if GRAPHQL_FUTURE
      @schema.execute_next(...)
    else
      @schema.execute(...)
    end
  end

  def test_it_streams_items
    res = exec_query "{
      i1: intList { ints }
      i2: intList { ints @stream }
    }"

    expected_first_response = {"i1"=>{"ints"=>[1, 2, 3]}, "i2"=>{ "ints" => [] }}
    assert_equal(expected_first_response, res["data"], "The undeferred response")

    patches = get_patches(res)
    expected_patches = [
      {data: expected_first_response, hasNext: true},
      {path: ["i2", "ints", 0], data: 4, hasNext: true},
      {path: ["i2", "ints", 1], data: 5, hasNext: true},
      {path: ["i2", "ints", 2], data: 6, hasNext: false},
    ]
    expected_patches.each_with_index do |patch, idx|
      assert_equal patch, patches[idx], "Patch idx=#{idx}"
    end

    assert_equal(expected_patches, patches, "each patch comes through")
    assert_equal({"i1"=>{"ints"=>[1, 2, 3]}, "i2"=>{"ints"=>[4, 5, 6]}}, final_result(res, patches)["data"], "The final response")
  end

  def test_it_renders_incremental_style_payloads
    res = exec_query "{
      i1: intList { ints }
      i2: intList { ints @stream }
    }"

    expected_first_response = {"i1"=>{"ints"=>[1, 2, 3]}, "i2"=>{ "ints" => [] }}
    assert_equal(expected_first_response, res["data"], "The undeferred response")

    patches = get_patches(res, h_method: :to_incremental_h)
    expected_patches = [
      {incremental: [{path: nil, data: expected_first_response}], hasNext: true},
      {incremental: [{path: ["i2", "ints", 0], data: 4}], hasNext: true},
      {incremental: [{path: ["i2", "ints", 1], data: 5}], hasNext: true},
      {incremental: [{path: ["i2", "ints", 2], data: 6}], hasNext: false},
    ]
    expected_patches.each_with_index do |patch, idx|
      assert_equal patch, patches[idx], "Patch idx=#{idx}"
    end
  end

  def test_it_handles_too_big_initial_count_by_returning_all
    res = exec_query "{
      intList { ints @stream(initialCount: 20) }
    }"
    expected_first_response = {"intList"=>{"ints"=>[1, 2, 3]}}
    assert_equal(expected_first_response, res["data"], "The undeferred response")
  end

  def test_it_works_with_dataloader
    res = exec_query "{
      intList {
        dataloadedInts @stream
      }
    }"

    expected_patches = [
      {:data=>{"intList"=>{"dataloadedInts"=>[]}}, hasNext: true},
      {:path=>["intList", "dataloadedInts", 0], :data=>3, hasNext: true},
      {:path=>["intList", "dataloadedInts", 1], :data=>3, hasNext: true},
      {:path=>["intList", "dataloadedInts", 2], :data=>3, hasNext: false}
    ]
    assert_equal expected_patches, get_patches(res)
  end

  def test_it_returns_initial_count
    res = exec_query "{
      intList { ints @stream(initialCount: 2) }
    }"

    expected_first_response = {"intList"=>{"ints"=>[1, 2]}}
    assert_equal(expected_first_response, res["data"], "The undeferred response")

    patches = get_patches(res)
    expected_patches = [
      {data: expected_first_response, hasNext: true},
      {path: ["intList", "ints", 2], data: 3, hasNext: false},
    ]
    assert_equal(expected_patches, patches, "each patch comes through")
    assert_equal({"intList"=>{"ints"=>[1, 2, 3]}}, final_result(res, patches)["data"], "The final response")
  end

  def test_it_accepts_if
    res = exec_query "{
      i1: intList { ints }
      i2: intList { ints @stream(if: false) }
      i3: intList { ints @stream(if: true, initialCount: 1) }
    }"

    expected_first_response = {
      "i1" => { "ints" => [1, 2, 3] },
      "i2" => { "ints" => [4, 5, 6] },
      "i3" => { "ints" => [7]},
    }
    assert_equal(expected_first_response, res["data"], "The undeferred response")

    patches = get_patches(res)
    expected_patches = [
      {data: expected_first_response, hasNext: true},
      {path: ["i3", "ints", 1], data: 8, hasNext: true },
      {path: ["i3", "ints", 2], data: 9, hasNext: false },
    ]
    assert_equal(expected_patches, patches)
  end

  def test_it_runs_nested_streams_that_all_have_the_same_name
    res = exec_query "{
      int
      intLists @stream {
        intLists @stream {
          ints @stream
        }
      }
    }"

    expected_initial_data = {"int"=>1, "intLists"=>[]}
    assert_equal(expected_initial_data, res["data"], "The undeferred response")

    patches = get_patches(res)
    expected_patches = [
      {:data=>expected_initial_data, hasNext: true},
      {path: ["intLists", 0], data: { "intLists" => [] }, hasNext: true},
      {path: ["intLists", 1], data: { "intLists" => [] }, hasNext: true},
      {path: ["intLists", 0, "intLists", 0], data: {"ints"=>[]}, hasNext: true},
      {path: ["intLists", 0, "intLists", 1], data: {"ints"=>[]}, hasNext: true},
      {path: ["intLists", 1, "intLists", 0], data: {"ints"=>[]}, hasNext: true},
      {path: ["intLists", 1, "intLists", 1], data: {"ints"=>[]}, hasNext: true},
      {path: ["intLists", 0, "intLists", 0, "ints", 0], data: 2, hasNext: true},
      {path: ["intLists", 0, "intLists", 0, "ints", 1], data: 3, hasNext: true},
      {path: ["intLists", 0, "intLists", 0, "ints", 2], data: 4, hasNext: true},
      {path: ["intLists", 0, "intLists", 1, "ints", 0], data: 5, hasNext: true},
      {path: ["intLists", 0, "intLists", 1, "ints", 1], data: 6, hasNext: true},
      {path: ["intLists", 0, "intLists", 1, "ints", 2], data: 7, hasNext: true},
      {path: ["intLists", 1, "intLists", 0, "ints", 0], data: 8, hasNext: true},
      {path: ["intLists", 1, "intLists", 0, "ints", 1], data: 9, hasNext: true},
      {path: ["intLists", 1, "intLists", 0, "ints", 2], data: 10, hasNext: true},
      {path: ["intLists", 1, "intLists", 1, "ints", 0], data: 11, hasNext: true},
      {path: ["intLists", 1, "intLists", 1, "ints", 1], data: 12, hasNext: true},
      {path: ["intLists", 1, "intLists", 1, "ints", 2], data: 13, hasNext: false},
    ]

    expected_patches.each_with_index do |expected_patch, idx|
      assert_equal expected_patch, patches[idx], "Patch idx=#{idx}"
    end
    assert_equal(expected_patches, patches)
  end

  def test_it_runs_nested_streams_with_different_names
    res = exec_query "{
      int
      i1: intLists @stream {
        i2: intLists @stream {
          i3: ints @stream
        }
      }
    }"

    expected_initial_data = {"int"=>1, "i1"=>[]}
    assert_equal(expected_initial_data, res["data"], "The undeferred response")

    expected_second_patch = { "i2" => [] }
    expected_third_patch = { "i3" => [] }
    patches = get_patches(res)
    expected_patches = [
      {:data=>expected_initial_data, hasNext: true},
      {path: ["i1", 0], data: expected_second_patch, hasNext: true},
      {path: ["i1", 1], data: expected_second_patch, hasNext: true},
      {path: ["i1", 0, "i2", 0], data: expected_third_patch, hasNext: true},
      {path: ["i1", 0, "i2", 1], data: expected_third_patch, hasNext: true},
      {path: ["i1", 1, "i2", 0], data: expected_third_patch, hasNext: true},
      {path: ["i1", 1, "i2", 1], data: expected_third_patch, hasNext: true},
      {path: ["i1", 0, "i2", 0, "i3", 0], data: 2, hasNext: true},
      {path: ["i1", 0, "i2", 0, "i3", 1], data: 3, hasNext: true},
      {path: ["i1", 0, "i2", 0, "i3", 2], data: 4, hasNext: true},
      {path: ["i1", 0, "i2", 1, "i3", 0], data: 5, hasNext: true},
      {path: ["i1", 0, "i2", 1, "i3", 1], data: 6, hasNext: true},
      {path: ["i1", 0, "i2", 1, "i3", 2], data: 7, hasNext: true},
      {path: ["i1", 1, "i2", 0, "i3", 0], data: 8, hasNext: true},
      {path: ["i1", 1, "i2", 0, "i3", 1], data: 9, hasNext: true},
      {path: ["i1", 1, "i2", 0, "i3", 2], data: 10, hasNext: true},
      {path: ["i1", 1, "i2", 1, "i3", 0], data: 11, hasNext: true},
      {path: ["i1", 1, "i2", 1, "i3", 1], data: 12, hasNext: true},
      {path: ["i1", 1, "i2", 1, "i3", 2], data: 13, hasNext: false},
    ]

    expected_patches.each_with_index do |expected_patch, idx|
      assert_equal expected_patch, patches[idx], "Patch idx=#{idx}"
    end
    assert_equal(expected_patches, patches)
  end

  def test_it_streams_with_lazy
    res = exec_query "{
      intList {
        lazyInts @stream
        intList {
          lazyInts @stream
        }
      }
    }"

    patches = get_patches(res)

    expected_patches = [
      { data: { "intList" => { "lazyInts" => [], "intList" => { "lazyInts" => [] } } }, hasNext: true },
      { path: ["intList", "lazyInts", 0], data: 1, hasNext: true },
      { path: ["intList", "lazyInts", 1], data: 2, hasNext: true },
      { path: ["intList", "lazyInts", 2], data: 3, hasNext: true },
      { path: ["intList", "intList", "lazyInts", 0], data: 4, hasNext: true },
      { path: ["intList", "intList", "lazyInts", 1], data: 5, hasNext: true },
      { path: ["intList", "intList", "lazyInts", 2], data: 6, hasNext: false },
    ]
    assert_equal expected_patches, patches
  end

  def test_it_streams_errors
    res = exec_query "{
      int
      intLists @stream {
        intLists @stream {
          executionErrors @stream
        }
      }
    }"
    patches = get_patches(res)

    legacy_expected_patches = [
      {:data=>{"int"=>1, "intLists"=>[]}, hasNext: true},
      {:path=>["intLists", 0], :data=>{"intLists"=>[]}, hasNext: true},
      {:path=>["intLists", 1], :data=>{"intLists"=>[]}, hasNext: true},
      {:path=>["intLists", 0, "intLists", 0],
      hasNext: true,
      data: { "executionErrors" => [nil] },
      :errors=>
        [{"message"=>"Broke!",
          "locations"=>[{"line"=>5, "column"=>11}],
          "path"=>["intLists", 0, "intLists", 0, "executionErrors", 0]}]},
      {:path=>["intLists", 0, "intLists", 1],
      hasNext: true,
      data: { "executionErrors" => [nil] },
      :errors=>
        [{"message"=>"Broke!",
          "locations"=>[{"line"=>5, "column"=>11}],
          "path"=>["intLists", 0, "intLists", 1, "executionErrors", 0]}]},
      {:path=>["intLists", 1, "intLists", 0], hasNext: true, data: { "executionErrors" => [nil] },
      :errors=>
        [{"message"=>"Broke!",
          "locations"=>[{"line"=>5, "column"=>11}],
          "path"=>["intLists", 1, "intLists", 0, "executionErrors", 0]}]},
      {:path=>["intLists", 1, "intLists", 1], hasNext: false, data: { "executionErrors" => [nil] },
      :errors=>
        [{"message"=>"Broke!",
          "locations"=>[{"line"=>5, "column"=>11}],
          "path"=>["intLists", 1, "intLists", 1, "executionErrors", 0]}]}
    ]

    future_expected_patches = [
      {hasNext: true, data: {"int" => 1, "intLists" => []}},
      {path: ["intLists", 0], hasNext: true, data: {"intLists" => []}},
      {path: ["intLists", 1], hasNext: true, data: {"intLists" => []}},
      {path: ["intLists", 0, "intLists", 0], hasNext: true, data: {"executionErrors" => []}},
      {path: ["intLists", 0, "intLists", 1], hasNext: true, data: {"executionErrors" => []}},
      {path: ["intLists", 1, "intLists", 0], hasNext: true, data: {"executionErrors" => []}},
      {path: ["intLists", 1, "intLists", 1], hasNext: true, data: {"executionErrors" => []}},
      {
        path: ["intLists", 0, "intLists", 0, "executionErrors", 0],
        hasNext: true,
        errors: [{"message" => "Broke!", "locations" => [{"line" => 5, "column" => 11}], "path" => ["intLists", 0, "intLists", 0, "executionErrors", 0, "executionErrors"]}]
      },
      {
        path: ["intLists", 0, "intLists", 1, "executionErrors", 0],
        hasNext: true,
        errors: [{"message" => "Broke!", "locations" => [{"line" => 5, "column" => 11}], "path" => ["intLists", 0, "intLists", 1, "executionErrors", 0, "executionErrors"]}]
      },
      {
        path: ["intLists", 1, "intLists", 0, "executionErrors", 0],
        hasNext: true,
        errors: [{"message" => "Broke!", "locations" => [{"line" => 5, "column" => 11}], "path" => ["intLists", 1, "intLists", 0, "executionErrors", 0, "executionErrors"]}]
      },
      {
        path: ["intLists", 1, "intLists", 1, "executionErrors", 0],
        hasNext: false,
        errors: [{"message" => "Broke!", "locations" => [{"line" => 5, "column" => 11}], "path" => ["intLists", 1, "intLists", 1, "executionErrors", 0, "executionErrors"]}]
      }
    ]

    exec_next_expected_patches = [
      {hasNext: true, data: {"int" => 1, "intLists" => []}},
      {path: ["intLists", 0], hasNext: true, data: {"intLists" => []}},
      {path: ["intLists", 1], hasNext: true, data: {"intLists" => []}},
      {path: ["intLists", 0, "intLists", 0], hasNext: true, data: {"executionErrors" => []}},
      {path: ["intLists", 0, "intLists", 1], hasNext: true, data: {"executionErrors" => []}},
      {path: ["intLists", 1, "intLists", 0], hasNext: true, data: {"executionErrors" => []}},
      {path: ["intLists", 1, "intLists", 1], hasNext: true, data: {"executionErrors" => []}},
      {
        path: ["intLists", 0, "intLists", 0, "executionErrors", 0],
        hasNext: true,
        errors: [{"message" => "Broke!", "locations" => [{"line" => 5, "column" => 11}], "path" => ["intLists", 0, "intLists", 0, "executionErrors", 0]}],
      },
      {
        path: ["intLists", 0, "intLists", 1, "executionErrors", 0],
        hasNext: true,
        errors: [{"message" => "Broke!", "locations" => [{"line" => 5, "column" => 11}], "path" => ["intLists", 0, "intLists", 1, "executionErrors", 0]}]
      },
      {
        path: ["intLists", 1, "intLists", 0, "executionErrors", 0],
        hasNext: true,
        errors: [{"message" => "Broke!", "locations" => [{"line" => 5, "column" => 11}], "path" => ["intLists", 1, "intLists", 0, "executionErrors", 0]}]
      },
      {
        path: ["intLists", 1, "intLists", 1, "executionErrors", 0],
        hasNext: false,
        errors: [{"message" => "Broke!", "locations" => [{"line" => 5, "column" => 11}], "path" => ["intLists", 1, "intLists", 1, "executionErrors", 0]}]
      }
    ]

    expected_patches = if GRAPHQL_FUTURE
      exec_next_expected_patches
    elsif @schema.directives["stream"] == GraphQL::Pro::FutureStream
      future_expected_patches
    else
      legacy_expected_patches
    end
    expected_patches.each_with_index do |expected_patch, i|
      assert_equal expected_patch, patches[i], "Patch idx=#{i}"
    end

    assert_equal(expected_patches, patches, "patches contain errors")
  end

  def test_skip_takes_priority
    res = exec_query "{
      ints @stream
      ints2: ints @stream @skip(if: true)
    }"

    assert_equal({ "ints" => [] }, res["data"], "The undeferred response")
    patches = get_patches(res)
    expected_patches = [
      {data: {"ints" => [] }, hasNext: true},
      {path: ["ints", 0], data: 1, hasNext: true},
      {path: ["ints", 1], data: 2, hasNext: true},
      {path: ["ints", 2], data: 3, hasNext: false},
    ]
    assert_equal(expected_patches, patches, "ints2 is not present because it was skipped")
  end

  def test_it_streams_a_root_field
    res = exec_query "{
      ints @stream
    }"

    patches = get_patches(res)
    assert_equal([
      { data: { "ints" => [] }, hasNext: true },
      { data: 1, path: ["ints", 0], hasNext: true },
      { data: 2, path: ["ints", 1], hasNext: true },
      { data: 3, path: ["ints", 2], hasNext: false },
    ], patches)
  end

  def test_it_includes_label_in_patches
    res = exec_query "{
      i1: ints @stream
      i2: ints @stream(label: \"stream-2\")
    }"

    patches = get_patches(res)
    expected_patches = [
      {:data=>{"i1"=>[], "i2"=>[]}, hasNext: true},
      {:path=>["i1", 0], :data=>1, hasNext: true},
      {:path=>["i1", 1], :data=>2, hasNext: true},
      {:path=>["i1", 2], :data=>3, hasNext: true},
      {:path=>["i2", 0], :label=>"stream-2", :data=>4, hasNext: true},
      {:path=>["i2", 1], :label=>"stream-2", :data=>5, hasNext: true},
      {:path=>["i2", 2], :label=>"stream-2", :data=>6, hasNext: false},
    ]
    expected_patches.each_with_index do |expected_patch, index|
      assert_equal expected_patch, patches[index], "Patch idx=#{index}"
    end
    assert_equal expected_patches, patches
  end

  def test_it_ignores_stream_on_non_lists
    # It _could_ raise an error here instead
    res = exec_query "{
      i1: int @stream
      i2: int @stream
    }"
    assert_equal({ "i1" => 1, "i2" => 2}, res["data"])
    assert_nil get_patches(res)
  end

  def test_it_creates_http_multipart
    res = exec_query "{
      ints @stream
      multibyteChars @stream
    }"

    multiparts = if (deferrals = res.context[:defer])
      is_first = true
      res = []
      deferrals.each do |result|
        res << result.to_http_multipart(first: is_first)
        is_first &= false
      end
      res
    end

    assert_equal 5, multiparts.size
    first_part, second_part, third_part, fourth_part, fifth_part = multiparts
    validate_multipart(first_part)
    validate_multipart(second_part)
    validate_multipart(third_part)
    validate_multipart(fourth_part)
    validate_multipart(fifth_part)
    expected_multiparts = [
      "\r\n---\r\nContent-Type: application/json\r\nContent-Length: 55\r\n\r\n{\"hasNext\":true,\"data\":{\"ints\":[],\"multibyteChars\":[]}}\r\n---",
      "\r\nContent-Type: application/json\r\nContent-Length: 43\r\n\r\n{\"path\":[\"ints\",0],\"hasNext\":true,\"data\":1}\r\n---",
      "\r\nContent-Type: application/json\r\nContent-Length: 43\r\n\r\n{\"path\":[\"ints\",1],\"hasNext\":true,\"data\":2}\r\n---",
      "\r\nContent-Type: application/json\r\nContent-Length: 43\r\n\r\n{\"path\":[\"ints\",2],\"hasNext\":true,\"data\":3}\r\n---",
      "\r\nContent-Type: application/json\r\nContent-Length: 59\r\n\r\n{\"path\":[\"multibyteChars\",0],\"hasNext\":false,\"data\":\"😈\"}\r\n-----",
    ]
    assert_equal expected_multiparts[0], first_part
    assert_equal expected_multiparts[1], second_part
    assert_equal expected_multiparts[2], third_part
    assert_equal expected_multiparts[3], fourth_part
    assert_equal expected_multiparts[4], fifth_part
  end

  def test_it_streams_http_multipart
    res = exec_query "{
      ints
      int2: ints @stream
    }"

    stream = res.context[:defer] || res.context[:streams]
    response = DummyResponse.new
    stream.stream_http_multipart(response)
    expected_headers = { "Content-Type" => "multipart/mixed; boundary=\"-\"" }
    assert_equal(expected_headers, response.headers)
    assert_equal(4, response.patches.size)
    assert response.patches.last.end_with?("\r\n-----"), "It adds a terminator"
  end

  # Rack::Test Setup
  def app
    builder = Rack::Builder.new
    builder.run DeferHelpers.create_streaming_sinatra_app(@schema)
    builder
  end

  def test_it_runs_with_sinatra_streaming
    post "/graphql", {query: "{ i1: ints i2: ints @stream }"}
    expected_body = '{"hasNext":true,"data":{"i1":[1,2,3],"i2":[]}}

{"path":["i2",0],"hasNext":true,"data":4}

{"path":["i2",1],"hasNext":true,"data":5}

{"path":["i2",2],"hasNext":false,"data":6}

'
    assert_equal expected_body, last_response.body
  end

  module LazyStreamAssertions
    def test_it_streams_a_lazy_enumerator
      counter = StreamAssertions::Counter.new
      str = "{ intLists { ints @stream } }"
      res = exec_query(str, context: { counter: counter })

      counter.increment
      patches = []
      res.context[:defer].each do |stream_res|
        patches << stream_res.to_h
        counter.increment
      end
      expected_patches = [
        {hasNext: true, data: {"intLists" => [{"ints" => []}, {"ints" => []}]}},
        # These aren't resolved until `each` forces it --
        # the `counter.increment` above is interleaved
        {path: ["intLists", 0, "ints", 0], hasNext: true, data: 3},
        {path: ["intLists", 0, "ints", 1], hasNext: true, data: 5},
        {path: ["intLists", 0, "ints", 2], hasNext: true, data: 7},
        {path: ["intLists", 1, "ints", 0], hasNext: true, data: 9},
        {path: ["intLists", 1, "ints", 1], hasNext: true, data: 11},
        {path: ["intLists", 1, "ints", 2], hasNext: false, data: 13}
      ]
      assert_equal expected_patches, patches
    end

    def test_it_works_with_graphql_batch
      res = exec_query("{ batchedInts @stream }")
      patches = get_patches(res)
      expected_patches = [
        {hasNext: true, data: {"batchedInts" => []}},
        {path: ["batchedInts", 0], hasNext: true, data: 1},
        {path: ["batchedInts", 1], hasNext: true, data: 2},
        {path: ["batchedInts", 2], hasNext: false, data: 3}
      ]
      assert_equal expected_patches, patches
    end

    def test_it_raises_errors_from_enumerators
      res = exec_query("{ errorEnumerator @stream }", context: { error_class: RuntimeError})
      resolved_patches = []
      err = assert_raises RuntimeError do
        res.context[:defer].each do |stream_res|
          resolved_patches << stream_res.to_h
        end
      end
      assert_equal "Boom!", err.message
      expected_patches = [
        {data: {"errorEnumerator" => []}, hasNext: true},
        {path: ["errorEnumerator", 0], data: 1, hasNext: true},
        {path: ["errorEnumerator", 1], data: 2, hasNext: true}
      ]
      assert_equal expected_patches, resolved_patches

      res = exec_query("{ errorEnumerator @stream }", context: { error_class: GraphQL::ExecutionError })
      patches = get_patches(res)
      expected_patches = [
        {data: {"errorEnumerator" => []}, hasNext: true},
        {path: ["errorEnumerator", 0], data: 1, hasNext: true},
        {path: ["errorEnumerator", 1], data: 2, hasNext: true},
        {path: ["errorEnumerator", 2], hasNext: false, errors: [{"message" => "Boom!"}]},
      ]
      assert_equal expected_patches, patches

      res = exec_query("{ errorEnumerator @stream }", context: { error_class: GraphQL::ExecutionError, enumerator_size: false })
      patches = get_patches(res)
      expected_patches = [
        {data: {"errorEnumerator" => []}, hasNext: true},
        {path: ["errorEnumerator", 0], data: 1, hasNext: true},
        {path: ["errorEnumerator", 1], data: 2, hasNext: true},
        {path: ["errorEnumerator", 2], hasNext: false, errors: [{"message" => "Boom! (peek)"}]},
      ]
      assert_equal expected_patches, patches
    end

    def test_it_streams_lazy_mutations_too
      counter = StreamAssertions::Counter.new
      str = "mutation GetInts { ints @stream }"
      res = exec_query(str, context: { counter: counter })

      counter.increment
      patches = []
      res.context[:defer].each do |stream_res|
        patches << stream_res.to_h
        counter.increment
      end
      expected_patches = [
        {hasNext: true, data: {"ints" => []}},
        # These aren't resolved until `each` forces it --
        # the `counter.increment` above is interleaved
        {path: ["ints", 0], hasNext: true, data: 3},
        {path: [ "ints", 1], hasNext: true, data: 5},
        {path: ["ints", 2], hasNext: false, data: 7},
      ]
      assert_equal expected_patches, patches
    end

    def test_it_emits_multiple_top_level_traces
      res = exec_query("{ ints @stream }")
      assert_equal res.query.object_id, res.context[:was_traced]

      result_count = 0
      res.context[:defer].each do |stream_res|
        expected_id = if result_count == 0
          res.query.object_id
        else
          stream_res.execution_result.partial.object_id
        end

        assert_equal expected_id, stream_res.execution_result.context[:was_traced], "Result idx=#{result_count} matched"
        result_count += 1
      end
      assert_equal 4, result_count
    end
  end
end
