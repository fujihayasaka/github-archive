# frozen_string_literal: true

require "test_helper"

class GHSAIDGeneratorTest < ActiveSupport::TestCase
  include GHSAIDGenerator

  test "generates a GHSA ID in the expected format" do
    ids = Array.new(1000) { generate_ghsa_id }

    assert(ids.all? { |id| AdvisoryDBToolkit::GHSAIDValidator::PATTERN.match?(id) })
  end

  test "generates distinct GHSA IDs" do
    ids = Array.new(1000) { generate_ghsa_id }

    assert_equal ids.count, ids.uniq.count
  end

  test "retries on collision" do
    id_1 = generate_ghsa_id
    id_2 = create(:advisory_review).ghsa_id
    id_3 = generate_ghsa_id

    stubs(:generate_ghsa_id)
      .returns(id_1)
      .returns(id_2)
      .returns(id_3)

    assert_equal generate_unique_ghsa_id, id_1 # No collision, uses id_1
    assert_equal generate_unique_ghsa_id, id_3 # Collides, skips id_2, uses id_3
  end
end
