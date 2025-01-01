# typed: strict
# frozen_string_literal: true

require "test_helper"

class RepositoryVulnerableFunctionReferenceTest < GitHub::TestCase
  context "validations" do
    test "raises an error if a required field is missing" do
      required_fields = %w[
        repository_vulnerability_exposure_update_id
        repository_vulnerability_alert_id
        repository_id
        vulnerable_version_range_id
        filename
        function_name
        commit_oid
        start_line
        start_column
        end_line
        end_column
      ]

      required_fields.each do |field|
        values = {
          repository_vulnerability_exposure_update_id: SecureRandom.random_number(1_000_000_000),
          repository_vulnerability_alert_id: SecureRandom.random_number(1_000_000_000),
          repository_id: SecureRandom.random_number(1_000_000_000),
          vulnerable_version_range_id: SecureRandom.random_number(1_000_000_000),
          filename: "main.py",
          function_name: "yaml.load",
          commit_oid: SecureRandom.hex(20),
          start_line: 10,
          start_column: 10,
          end_line: 11,
          end_column: 20,
        }.with_indifferent_access

        values[field] = nil

        assert_raises ActiveRecord::RecordInvalid do
          RepositoryVulnerableFunctionReference.create!(
            values,
          )
        end
      end
    end
  end

  test "generates the blob path for a given function reference" do
    function_reference = create(:repository_vulnerable_function_reference)

    assert_equal "/#{function_reference.repository.nwo}/blob/#{function_reference.commit_oid}/#{function_reference.filename}#L#{function_reference.start_line}-L#{function_reference.end_line}", function_reference.blob_path
  end
end
