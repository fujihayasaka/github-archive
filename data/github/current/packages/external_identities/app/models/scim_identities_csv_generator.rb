# typed: true
# frozen_string_literal: true

# This is the runner for the ghe-scim-identities-csv command, by way of script/ghe-scim-identities-csv.

class ScimIdentitiesCSVGenerator

  class Error < StandardError
  end

  HEADER = "external_identity_id,user_id,login,user_name,external_id,scim_user_id,groups".freeze

  # Create a new CSV generator.
  #
  # output_io:     - An open IO handle to print the CSV results to. Usually
  #                  either a file in /tmp, or STDOUT.
  # header:        - Whether or not to include the CSV header in the output.
  #                  Default is false.
  def initialize(output_io:, header: false)
    raise Error, "SCIM identities csv generation only works in enterprise" unless GitHub.enterprise?
    raise Error, "SCIM identities csv generation does not work when SCIM is disabled. SCIM identities are destroyed once SCIM is disabled." unless GitHub.global_business&.enterprise_server_scim_enabled?
    @output = output_io
    @header   = header
  end

  # Prints a CSV in @output, where each row cotains the following information:
  #
  #  * external_identity_id
  #  * user id
  #  * login
  #  * user_name
  #  * external_id
  #  * scim_user_id
  #  * groups
  #
  def run
    batch_size = (ENV["SCIM_BATCH_SIZE"] || 100).to_i
    start = ENV["SCIM_START_INDEX"].to_i

    iter = GitHub::QueryBatching::ScopeIterator
      .new(ExternalIdentity.joins(:user), start: start, batch_size: batch_size)

    csv = CSV.new(@output, headers: HEADER, write_headers: header?)
    rows = complete_results(iter, csv)

    if csv.lineno == 0
      $stderr.puts "Failed to find SCIM identity records."
      nil
    end
  end

  private

  # For each batch builds the list of groups for each external identity,
  # and completes the query results by adding to each row.
  def complete_results(iter, csv)
    iter.batches.each do |batch|
      res = batch.pluck(:id, :user_id, "users.login", :user_name, :external_id, :guid)
      external_identity_ids = res.map(&:first)

      groups_by_external_identity = ExternalIdentityGroupMembership.joins(:external_group)
        .where(external_identity_id: external_identity_ids)
        .select(
          "external_identity_id",
          "external_groups.display_name"
        )
        .group_by(&:external_identity_id)

      res.each do |row|
        external_identity_id, user_id, login, user_name, external_id, scim_user_id = *row
        groups = groups_by_external_identity[external_identity_id]
        group_names = groups&.pluck(:display_name)&.join(", ")
        csv << [external_identity_id, user_id, login, user_name, external_id, scim_user_id, group_names]
      end
    end
  end

  def header?
    @header
  end
end
