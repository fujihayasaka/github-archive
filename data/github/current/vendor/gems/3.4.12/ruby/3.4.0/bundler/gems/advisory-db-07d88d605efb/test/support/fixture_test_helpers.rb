# frozen_string_literal: true

module FixtureTestHelpers
  def load_cve_fixture(cve_id)
    Rails.root.join("test/fixtures/cve_json_samples/#{cve_id}.json").read
  end
end

module ActiveSupport
  class TestCase
    include FixtureTestHelpers
  end
end
