# typed: true
# frozen_string_literal: true

require "test_helper"

class ApiMiddlewareCorsTest < GitHub::TestCase
  setup do
    @app = Api::Middleware::Cors.new(->(_) { [200, {}, ["Ok!\n"]] })
  end

  test "does not include Content-Type for OPTIONS requests" do
    _, headers, _ = @app.call({ "REQUEST_METHOD" => "OPTIONS" })
    refute_includes headers, "Content-Type"
  end
end
