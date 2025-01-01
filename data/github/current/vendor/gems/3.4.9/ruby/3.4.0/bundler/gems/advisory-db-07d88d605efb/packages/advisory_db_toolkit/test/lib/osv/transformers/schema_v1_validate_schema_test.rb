# frozen_string_literal: true

require "test_helper"

class OSVTransformersSchemaV1ValidateSchemaTest < Minitest::Test
  def setup
    @subject = AdvisoryDBToolkit::OSV::Transformers::SchemaV1
  end

  def test_checks_the_validity_of_parsed_json_against_the_schema
    minimally_valid_osv_hash = {
      "id" => "1234",
      "modified" => "2021-01-14T15:50:11Z",
    }
    @subject.validate_schema!(minimally_valid_osv_hash)
  end

  def test_raises_schemavalidationerror_for_invalid_parsed_json
    invalid_osv_hash = {}
    assert_raises(@subject::SchemaValidationError) do
      @subject.validate_schema!(invalid_osv_hash)
    end
  end
end
