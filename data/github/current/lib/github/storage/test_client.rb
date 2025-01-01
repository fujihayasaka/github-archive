# typed: true
# frozen_string_literal: true

class GitHub::Storage::TestClient < GitHub::Storage::Client
  attr_reader :stubs
  def initialize
    @stubs = Faraday::Adapter::Test::Stubs.new
    yield @stubs if block_given?
  end

  private

  def build_faraday(f)
    f.adapter :test, stubs
  end
end
