# frozen_string_literal: true
require "test_helper"

class GraphQLProStreamTest < Minitest::Test
  parallelize_me!

  include Rack::Test::Methods
  include DeferHelpers
  include StreamAssertions

  if GRAPHQL_FUTURE
    include StreamAssertions::LazyStreamAssertions
  end

  class LegacyStreamSchema < StreamSchema
    use GraphQL::Pro::Stream
    use GraphQL::Dataloader
  end

  def setup
    @schema = LegacyStreamSchema
  end

  def test_it_accepts_if
    super
  end

  def test_it_sets_up_the_expected_internal_state
    res = @schema.execute "{
      ints @stream
    }"
    deferrals = res.context[:defer].deferrals
    root_deferral = deferrals.first

    assert_instance_of GraphQL::Pro::Defer::RootDeferral, root_deferral
    assert_nil root_deferral.path
    assert_nil root_deferral.errors
    assert_equal({"ints" => []}, root_deferral.data)
  end
end
