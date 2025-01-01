# typed: true
# frozen_string_literal: true

require "test_helper"

class SamlMappingCSVUpdaterTest < GitHub::TestCase
  fixtures do
    user = create :user, login: "monalisa"
    @mapping = create :user_saml_mapping, user: user, name_id: user.login, name_id_format: "urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified"
  end

  sig { params(header: T::Boolean).returns(StringIO) }
  def generate_new_csv(header: false)
    create_io = StringIO.new
    create_generator = SamlMappingCSVGenerator.new output_io: create_io, header: header
    create_generator.run
    create_io.rewind

    create_io
  end

  sig { params(csv: String, header: T::Boolean).returns(T.any(CSV::Table, T::Array[T::Array[T.untyped]])) }
  def update_csv(csv, header: false)
    update_io = T.must(csv)
    update_generator = SamlMappingCSVUpdater.new input_io: update_io, header: header
    update_generator.run
    updated_csv = CSV.parse update_io

    updated_csv
  end

  # Responsible for updating the name_id in the csv when headers are present
  sig { params(csv_data: StringIO, mapping_id: Integer, new_name_id: String).returns(String) }
  def update_name_id(csv_data, mapping_id, new_name_id)
    updated_csv_data = CSV.generate do |csv|
      csv << %w[mapping_id user_id login name_id name_id_format]

      CSV.parse(csv_data, headers: true) do |row|
        if row[T.unsafe("mapping_id")].to_i == mapping_id
          row[T.unsafe("name_id")] = new_name_id
        end
        csv << row
      end
    end

    updated_csv_data
  end

  context "#run" do
    test "updates mappings without headers" do
      # generate new csv first
      create_io = generate_new_csv(header: false)

      # update the name_id
      content = create_io.string.chomp
      values = content.split(",")
      new_name_id = "new_name_id"
      values[3] = new_name_id
      modified_content = values.join(",")
      create_io.reopen(modified_content)

      # run the updater on the updated csv
      updated_csv = update_csv(T.must(create_io.read))

      row = T.must(updated_csv.first)
      updated_entry = SamlMapping.find(@mapping.id)

      assert_equal @mapping.id.to_s, row[0]
      assert_equal @mapping.user_id.to_s, row[1]
      assert_equal @mapping.user.login, row[2]
      refute_equal @mapping.name_id, row[3]
      assert_equal new_name_id, row[3]
      assert_equal new_name_id, updated_entry.name_id
      refute_equal @mapping.name_id, updated_entry.name_id
      assert_equal @mapping.name_id_format, row[4]
    end

    test "updates mappings with headers" do
      # generate new csv first
      create_io = generate_new_csv(header: true)

      # update the name_id
      new_name_id = "new_name_id"
      update_io = update_name_id(T.must(create_io), @mapping.id, new_name_id)

      # run the updater on the updated csv
      updated_csv = update_csv(update_io, header: true)

      row = T.must(updated_csv[1])
      updated_entry = SamlMapping.find(@mapping.id)

      assert_equal @mapping.id.to_s, row[0]
      assert_equal @mapping.user_id.to_s, row[1]
      assert_equal @mapping.user.login, row[2]
      refute_equal @mapping.name_id, row[3]
      assert_equal new_name_id, row[3]
      assert_equal new_name_id, updated_entry.name_id
      refute_equal @mapping.name_id, updated_entry.name_id
      assert_equal @mapping.name_id_format, row[4]
    end

    test "does not update mappings when dry_run: true" do
      # generate new csv first
      create_io = generate_new_csv(header: true)

      # update the name_id
      new_name_id = "new_name_id"
      update_io = update_name_id(T.must(create_io), @mapping.id, new_name_id)

      bind_params = { id: "#{@mapping.id}", name_id: "new_name_id", name_id_format: "urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified" }
      expected_output_pattern = "UPDATE saml_mappings SET saml_mappings.name_id = :name_id, saml_mappings.name_id_format = :name_id_format, saml_mappings.updated_at = NOW() " +
        "WHERE saml_mappings.id = :id LIMIT 1 #{bind_params}\n"

      assert_output(expected_output_pattern) do
        updater = SamlMappingCSVUpdater.new input_io: update_io, header: true, dry_run: true
        updater.run
      end

      assert_equal SamlMapping.find(@mapping.id), @mapping
    end

  end
end if GitHub.enterprise?
