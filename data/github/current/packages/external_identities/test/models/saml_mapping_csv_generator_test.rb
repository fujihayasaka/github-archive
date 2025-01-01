# typed: false
# frozen_string_literal: true

require "test_helper"

class SamlMappingCSVGeneratorTest < GitHub::TestCase
  fixtures do
    @mapping = create :user_saml_mapping
  end

  context "#run" do
    test "returns mappings without headers" do
      io = StringIO.new
      generator = SamlMappingCSVGenerator.new output_io: io, header: false
      generator.run
      io.rewind
      csv = CSV.parse io.read
      row = csv.first

      assert_equal @mapping.id.to_s, row[0]
      assert_equal @mapping.user_id.to_s, row[1]
      assert_equal @mapping.user.login, row[2]
      assert_equal @mapping.name_id, row[3]
      assert_equal @mapping.name_id_format, row[4]
    end

    test "returns mappings with headers" do
      io = StringIO.new
      generator = SamlMappingCSVGenerator.new output_io: io, header: true
      generator.run
      io.rewind
      csv = CSV.parse io.read
      header = csv.first
      row = csv.second

      assert_equal "mapping_id", header[0]
      assert_equal "user_id", header[1]
      assert_equal "login", header[2]
      assert_equal "name_id", header[3]
      assert_equal "name_id_format", header[4]

      assert_equal @mapping.id.to_s, row[0]
      assert_equal @mapping.user_id.to_s, row[1]
      assert_equal @mapping.user.login, row[2]
      assert_equal @mapping.name_id, row[3]
      assert_equal @mapping.name_id_format, row[4]
    end
  end
end if GitHub.enterprise?
