# typed: true
# frozen_string_literal: true

module Business::AdvancedSecurityCommittersGenerator
  class EntityNotBillableError < ArgumentError; end
  GET_COMMITTERS_MAX_PAGE_SIZE = 200000
  HEADERS = ["User login", "Organization / repository", "Last pushed date", "Last pushed email"].freeze

  def self.get_committers(entity, committer_type: :ACTIVE_COMMITTERS, repository_ids: nil)
    data = Business::AdvancedSecurityCommittersGenerator.get_committers_paginated(entity, limit: GET_COMMITTERS_MAX_PAGE_SIZE, committer_type:, repository_ids:)
    out = data.committers
    while data.next_cursor.present?
      data = Business::AdvancedSecurityCommittersGenerator.get_committers_paginated(entity, limit: GET_COMMITTERS_MAX_PAGE_SIZE, cursor: data.next_cursor, committer_type:, repository_ids:)
      out += data.committers
    end
    out
  end

  def self.generate_csv(entity:, committer_type: :ACTIVE_COMMITTERS, repository_ids: nil)
    CSV.generate do |csv|
      csv << Business::AdvancedSecurityCommittersGenerator::HEADERS
      get_committers(entity, committer_type: committer_type, repository_ids: repository_ids).each do |row|
        csv << [row.display_login, row.name_with_display_owner, row.pushed_at.to_time.utc.strftime("%Y-%m-%d"), row.email]
      end
    end
  end

  # generate the data used by the api json output
  def self.generate_json(owner, page: 1, per_page: 30, committer_type: :ACTIVE_COMMITTERS, repository_ids: nil)
    by_repository = get_committers(owner, committer_type:, repository_ids:).group_by(&:name_with_display_owner)

    repository_nwos = if owner.advanced_security_purchased?
      by_repository.keys
    else
      []
    end

    # the total number of repositories with advanced security enabled
    total_count = repository_nwos.size

    license_info = if owner.advanced_security_billable_entity?
      summary = owner.advanced_security_summary

      {
        total_advanced_security_committers: summary.active_committers,
        maximum_advanced_security_committers: summary.maximum_committers,
        purchased_advanced_security_committers: (owner.advanced_security_license.seats if owner.advanced_security_license.seats.nonzero?)
      }.compact
    else
      {
        total_advanced_security_committers: owner.advanced_security_seats_used,
      }
    end

    distinct_users = Set.new

    paged_repository_nwos = repository_nwos.slice((page - 1) * per_page, per_page)

    items = by_repository.slice(*paged_repository_nwos).map do |repository_nwo, rows|
      { name: repository_nwo, advanced_security_committers: 0, advanced_security_committers_breakdown: [] }.tap do |breakdown|
        rows.each do |row|
          distinct_users.add(row.id)
          breakdown[:advanced_security_committers] += 1
          breakdown[:advanced_security_committers_breakdown] << {
            user_login: row.display_login,
            last_pushed_date: row.pushed_at.to_time.utc.strftime("%Y-%m-%d"),
            last_pushed_email: row.email,
          }
        end
      end
    end

    # Are there are more pages of repos?
    more_repos = per_page * page < total_count

    # If there are no more pages of repos and we are on the first page, then we can
    # just return the number of users as they will cover all
    # This ensures that we do not show a potentially inconsistent number of users
    # when we have complete data.
    total_advanced_security_committers = if !more_repos && page == 1
      distinct_users.size
    else
      # otherwise use the value that we also use in the UI
      owner.advanced_security_seats_used
    end

    {
      repositories: items,
      total_count: total_count,
      total_advanced_security_committers: total_advanced_security_committers,
      **license_info,
    }
  end

  def self.get_committers_paginated(entity, limit: nil, cursor: nil, committer_type: :ACTIVE_COMMITTERS, repository_ids: nil)
    return [] if entity.nil?

    # support overriding the timeout in Stafftools when downloading very large CSVs
    patient_client = GitHub::Turboghas.new_client(connection: GitHub::Turboghas.connection(timeout: 10))

    if entity.is_a?(User)
      response = patient_client.get_committers_for_owner(owner_id: entity.id, limit:, cursor:, committer_type:, repository_ids:)
    else
      response = patient_client.get_committers_for_business(business_id: entity.id, limit:, cursor:, committer_type:, repository_ids:)
    end

    unless response&.error.nil?
      e = ::GitHub::Turboghas::ResponseError.new(response.error.msg)
      Failbot.report(e, catalog_service: "github/advanced_security_billing")
      raise e
    end
    response.data
  end
end
