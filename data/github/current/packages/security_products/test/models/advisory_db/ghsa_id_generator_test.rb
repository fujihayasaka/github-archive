# typed: true
# frozen_string_literal: true

require "test_helper"

class AdvisoryDbGhsaIdGeneratorTest < GitHub::TestCase
  include AdvisoryDB::GhsaIdGenerator

  fixtures do
    @id_pattern = AdvisoryDB.valid_ghsa_id_pattern
  end

  test "generates a GHSA ID in the expected format" do
    ids = 1000.times.map { generate_ghsa_id }

    assert ids.all? { |id| @id_pattern.match?(id) }
  end

  test "generates distinct GHSA IDs" do
    ids = 1000.times.map { generate_ghsa_id }

    assert_equal ids.count, ids.uniq.count
  end

  test "retries on collision" do
    id_1 = generate_ghsa_id
    id_2 = create(:vulnerability).ghsa_id
    id_3 = create(:vulnerability, ghsa_id: generate_unique_ghsa_id).ghsa_id
    id_4 = generate_ghsa_id

    stubs(:generate_ghsa_id)
      .returns(id_1)
      .returns(id_2)
      .returns(id_3)
      .returns(id_4)

    assert_equal generate_unique_ghsa_id, id_1 # No collision, uses id_1
    assert_equal generate_unique_ghsa_id, id_4 # Collides, skips id_2 and id_3, uses id_4
  end
end
