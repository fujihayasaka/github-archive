# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryAdvisoryAffectedProductTest < GitHub::TestCase
  include StringFromBinaryTestHelper
  fixtures do
    @repository_advisory = create(:repository_advisory)
    @repository_advisory_affected_product = create(:repository_advisory_affected_product)
  end

  test "must be associated with a repository advisory" do
    @repository_advisory_affected_product.repository_advisory_id = nil

    refute @repository_advisory_affected_product.save
  end

  test "must be associated with a repository advisory that actually exists" do
    repository_advisory_id = T.must(T.must(RepositoryAdvisory.last).id) + 1
    refute RepositoryAdvisory.find_by(id: repository_advisory_id)
    assert @repository_advisory_affected_product.valid?

    @repository_advisory_affected_product.repository_advisory_id = repository_advisory_id

    refute @repository_advisory_affected_product.valid?
  end

  test "has a field for the affected versions" do
    RepositoryAdvisoryAffectedProduct.create!(
      affected_versions: "< 1.0.1",
      repository_advisory_id: @repository_advisory.id
    )
  end

  test "has a field for the ecosystem" do
    RepositoryAdvisoryAffectedProduct.create!(
      ecosystem: "npm",
      repository_advisory_id: @repository_advisory.id
    )
  end

  test "has a field for the package" do
    RepositoryAdvisoryAffectedProduct.create!(
      package: "nodemon",
      repository_advisory_id: @repository_advisory.id
    )
  end

  test "has a field for the patched versions" do
    RepositoryAdvisoryAffectedProduct.create!(
      patches: "1.0.1",
      repository_advisory_id: @repository_advisory.id
    )
  end

  [:affected_versions, :ecosystem, :package, :patches].each do |field|
    test "supports emoji for #{field}" do
      encoded_value = "testing ❤️🤠 有用"
      encoded_value2 = "testing \xE2\x9D\xA4\xEF\xB8\x8F\xF0\x9F\xA4\xA0 \xE6\x9C\x89\xE7\x94\xA8"
      repository_advisory_affected_product = create(:repository_advisory_affected_product, field => encoded_value)

      assert_multibyte_tracked_changes(repository_advisory_affected_product, field, encoded_value, encoded_value2)
    end
  end

  # max field lengths for strings that are sent to to AdvisoryDB
  # in these cases, we are limited to the column lengths for these fields in AdvisoryDB
  # see here for the column definitions we are trying to fit into: https://github.com/github/advisory-db/blob/524b29f1afaa165498ff7639b3e4f75c3132aa1a/db/structure.sql#L103
  # Note that in dotcom, affected_versions and patches are `blob` column types, and so can fit a lot more text than the corresponding AdvisoryDB column, thus necessitating this test
  {
    ecosystem: 50,
    package: 100,
    patches: 1024,
    affected_versions: 1024,
  }.each do |field, max_length|
    test "is invalid when field #{field} is longer than #{max_length}" do
      assert @repository_advisory_affected_product.valid?
      # make the field 1 character too long
      @repository_advisory_affected_product.assign_attributes(field => ("a" * (max_length + 1)))
      refute @repository_advisory_affected_product.valid?
      # make it the max length
      @repository_advisory_affected_product.assign_attributes(field => ("a" * max_length))
      assert @repository_advisory_affected_product.valid?
    end
  end

  test "requires a value for affected versions if the repository advisory is published" do
    published_repository_advisory = create(:published_repository_advisory)
    repository_advisory_affected_product = create(:repository_advisory_affected_product,
      repository_advisory: published_repository_advisory,
      affected_versions: "< 1.0.0"
    )
    assert repository_advisory_affected_product.valid?

    repository_advisory_affected_product.affected_versions = nil
    refute repository_advisory_affected_product.valid?
  end
end
