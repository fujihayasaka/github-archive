# typed: true
# frozen_string_literal: true

# This is the runner for the ghe-saml-mapping-csv command, by way of script/ghe-saml-mapping-csv.

class SamlMappingCSVGenerator

  class Error < StandardError
  end

  HEADER = "mapping_id,user_id,login,name_id,name_id_format".freeze

  # Create a new CSV generator.
  #
  # output_io:     - An open IO handle to print the CSV results to. Usually
  #                  either a file in /tmp, or STDOUT.
  # header:        - Whether or not to include the CSV header in the output.
  #                  Default is false.
  def initialize(output_io:, header: false)
    raise Error, "SAML mapping csv generation only works in enterprise" unless GitHub.enterprise?
    raise Error, "SAML mapping csv generation does not work when SCIM is enabled. SAML mappings are not used to associate a user with their external identity once SCIM is enabled." if GitHub.global_business.enterprise_server_scim_enabled?
    @output = output_io
    @header   = header
  end

  # Prints a CSV in @output, where each row cotains the following information:
  #
  #  * saml mapping id
  #  * user id
  #  * login
  #  * name id
  #  * name id format
  #
  def run
    batch_size = (ENV["SAML_BATCH_SIZE"] || 100).to_i
    start = ENV["SAML_START_INDEX"].to_i

    iter = GitHub::QueryBatching::ScopeIterator
      .new(SamlMapping.joins(:user), start: start, batch_size: batch_size)
      .pluck(:id, :user_id, "users.login", :name_id, :name_id_format)

    csv = csv = CSV.new(@output, headers: HEADER, write_headers: header?)
    rows = complete_results(iter.rows, csv)

    if csv.lineno == 0
      $stderr.puts "Failed to find Saml Mapping records."
      nil
    end
  end

  private

  # Completes the query results by adding to each row, the count of different
  # organizations the user belongs to.
  def complete_results(results, csv)
    results.each do |row|
      saml_mapping_id, user_id, login, name_id, name_id_format = *row
      csv << [saml_mapping_id, user_id, login, name_id, name_id_format]
    end
  end

  def header?
    @header
  end
end
