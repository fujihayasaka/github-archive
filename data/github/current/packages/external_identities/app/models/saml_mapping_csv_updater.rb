# typed: false
# frozen_string_literal: true

# This is the runner for the ghe-saml-mapping-csv command, by way of script/ghe-saml-mapping-csv.

class SamlMappingCSVUpdater

  class Error < StandardError
  end

  # Update SamlMapping with the CSV.
  #
  # input_io:     - An open IO handle to print the CSV results to. Usually
  #                  either a file in /tmp, or STDIN.
  # dry_run:      - Print the SQL instead of running it
  # header:       - Set to true if the input contains a header row
  def initialize(input_io:, dry_run: false, header: false)
    raise Error, "SAML mapping csv update only works in enterprise" unless GitHub.enterprise?
    raise Error, "SAML mapping csv update does not work when SCIM is enabled. SAML mappings are not used to associate a user with their external identity once SCIM is enabled." if GitHub.global_business.enterprise_server_scim_enabled?
    @input         = input_io
    @dry_run       = dry_run
    @header        = header
  end

  def input_header?
    @header
  end

  # Updates records from an input CSV in @input_io, where each row contains the following information:
  #
  #  * saml mapping id
  #  * <not used>
  #  * <not used>
  #  * name id
  #  * name id format
  #
  def run
    csv = CSV.new(@input).drop(input_header? ? 1 : 0)

    csv.each do |row|
      mapping_id, _, _, name_id, name_id_format = *row
      sql_template = <<-SQL
        UPDATE saml_mappings
        SET saml_mappings.name_id = :name_id, saml_mappings.name_id_format = :name_id_format, saml_mappings.updated_at = NOW()
        WHERE saml_mappings.id = :id
        LIMIT 1
      SQL

      begin
        sql = Arel.sql(sql_template, id: mapping_id, name_id: name_id, name_id_format: name_id_format)
      rescue Arel::BindError
        STDERR.puts "Error with input data at line #{csv.lineno}: mapping_id=#{mapping_id.inspect} name_id=#{name_id.inspect} name_id_format=#{name_id_format.inspect}"
        next
      end

      if @dry_run
        puts "#{sql.sql_with_placeholders.strip.squeeze(" ").delete("\n")} #{sql.named_binds}"
      else
        SamlMapping.connection.update(sql)
      end
    end
  end
end
