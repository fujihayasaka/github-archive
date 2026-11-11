# frozen_string_literal: true
require "test_helper"

class GraphQLProFutureStreamTest < Minitest::Test
  parallelize_me!

  include Rack::Test::Methods
  include DeferHelpers
  include StreamAssertions

  module StreamTrace
    def execute_multiplex(multiplex:)
      multiplex.queries.each { |q| q.context[:was_traced] = q.object_id }
      super
    end
  end

  def setup
    @schema = Class.new(StreamSchema) do
      use GraphQL::Pro::FutureStream
      use GraphQL::Dataloader
      trace_with StreamTrace
    end
  end

  def test_it_streams_a_lazy_enumerator
    counter = StreamAssertions::Counter.new
    str = "{ intLists { ints @stream } }"
    res = @schema.execute(str, context: { counter: counter })

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
    res = @schema.execute("{ batchedInts @stream }")
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
    res = @schema.execute("{ errorEnumerator @stream }", context: { error_class: RuntimeError})
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

    res = @schema.execute("{ errorEnumerator @stream }", context: { error_class: GraphQL::ExecutionError })
    patches = get_patches(res)
    expected_patches = [
      {data: {"errorEnumerator" => []}, hasNext: true},
      {path: ["errorEnumerator", 0], data: 1, hasNext: true},
      {path: ["errorEnumerator", 1], data: 2, hasNext: true},
      {path: ["errorEnumerator", 2], hasNext: false, errors: [{"message" => "Boom!"}]},
    ]
    assert_equal expected_patches, patches

    res = @schema.execute("{ errorEnumerator @stream }", context: { error_class: GraphQL::ExecutionError, enumerator_size: false })
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
    res = @schema.execute(str, context: { counter: counter })

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
    res = @schema.execute("{ ints @stream }")
    assert_equal res.query.object_id, res.context[:was_traced]

    result_count = 0
    res.context[:defer].each do |stream_res|
      expected_id = if result_count == 0
        res.query.object_id
      else
        stream_res.execution_result.partial.object_id
      end

      assert_equal expected_id, stream_res.execution_result.context[:was_traced]
      result_count += 1
    end
    assert_equal 4, result_count
  end
end
