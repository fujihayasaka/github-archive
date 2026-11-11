# frozen_string_literal: true
require "test_helper"

class GraphQLProFutureStreamTest < Minitest::Test
  parallelize_me!

  include Rack::Test::Methods
  include DeferHelpers
  include StreamAssertions
  include StreamAssertions::LazyStreamAssertions



  def setup
    @schema = Class.new(StreamSchema) do
      use GraphQL::Pro::FutureStream
      use GraphQL::Dataloader
    end
  end

end
