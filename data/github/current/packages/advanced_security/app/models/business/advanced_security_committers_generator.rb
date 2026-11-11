# typed: strict
# frozen_string_literal: true

module Business::AdvancedSecurityCommittersGenerator
  class EntityNotBillableError < ArgumentError; end
  GET_COMMITTERS_MAX_PAGE_SIZE = 200000
  HEADERS = ["User login", "Organization / repository", "Last pushed date", "Last pushed email"].freeze
  GET_COMMITTERS_PAGINATED_RETRIES = 3
  LICENSIFY_CUSTOMER_LICENSES_PAGE_SIZE = 5000

  sig do
    params(
      entity: T.any(User, Business, Organization),
      committer_type: Symbol,
      repository_ids: T.nilable(T::Array[Integer]),
      sku: GitHub::Turboghas::SKU,
    ).returns(T::Array[::Turboghas::Proto::GetCommittersResponse::Committer])
  end
  def self.get_committers(entity, committer_type: :ACTIVE_COMMITTERS, repository_ids: nil, sku: GitHub::Turboghas::SKU::Bundled)
    # Use Licensify for ACTIVE_COMMITTERS on dotcom when entity has a customer_id.
    # Organizations that belong to an enterprise are excluded — they fall back to the
    # paginated TurboGHAS path. Standalone orgs (no enterprise) can still use Licensify.
    if !GitHub.enterprise? && !(entity.is_a?(Organization) && entity.business_membership.present?) && committer_type == :ACTIVE_COMMITTERS && Licensing::Customer.id_for(entity).present?
      return get_committers_from_licensify(entity, sku: sku, repository_ids: repository_ids)
    end

    data = Business::AdvancedSecurityCommittersGenerator.get_committers_paginated(entity, limit: GET_COMMITTERS_MAX_PAGE_SIZE, committer_type:, repository_ids:, sku:)
    out = data.committers.to_a
    while data.next_cursor.present?
      data = Business::AdvancedSecurityCommittersGenerator.get_committers_paginated(entity, limit: GET_COMMITTERS_MAX_PAGE_SIZE, cursor: data.next_cursor, committer_type:, repository_ids:, sku:)
      out += data.committers.to_a
    end
    out
  end

  sig do
    params(
      entity: T.any(User, Business, Organization),
      sku: GitHub::Turboghas::SKU,
      repository_ids: T.nilable(T::Array[Integer]),
    ).returns(T::Array[::Turboghas::Proto::GetCommittersResponse::Committer])
  end
  def self.get_committers_from_licensify(entity, sku: GitHub::Turboghas::SKU::Bundled, repository_ids: nil)
    GitHub.logger.info(
      "get_committers_from_licensify called",
      "code.namespace" => "Business::AdvancedSecurityCommittersGenerator",
      "code.function" => "get_committers_from_licensify",
      "gh.licensing.get_committers_from_licensify.repository_count" => repository_ids&.size || 0
    )

    customer_id = Licensing::Customer.id_for(entity)
    return [] if customer_id.nil?

    product = Licensing::Licensify::LicensifyProduct.from_turboghas_sku(sku)

    # Fetch all active customer licenses with pagination using GetCustomerLicenses.
    # Licensify's Faraday client handles transient retries internally.
    licenses = T.let([], T::Array[::Licensify::Services::V1::CustomerLicense])
    offset = 0
    begin
      loop do
        response = Licensing.get_customer_licenses(
          customer_id,
          product: product,
          statuses: [::Licensify::Services::V1::LicenseStatus::LICENSE_STATUS_ACTIVE],
          limit: LICENSIFY_CUSTOMER_LICENSES_PAGE_SIZE,
          offset: offset,
        )
        licenses.concat(response.customerLicenses.to_a)
        offset += LICENSIFY_CUSTOMER_LICENSES_PAGE_SIZE
        break if licenses.size >= response.total
      end
    rescue Licensing::Licensify::LicensifyRequestFailed => e
      Failbot.report(e, catalog_service: "github/licensing")
      raise e
    end

    # Expand licenses into per-user, per-repo pairs from enablements.
    # Enablements with REPO-type enablementIds contain strings in the format "REPO_ID:PUSHED_AT".
    # Skip licenses that are still marked "active" but have already expired (billing
    # keeps them active through the end of the month).
    now = Time.now.utc

    # Build a list of {user_id, repo_id, pushed_at} entries from license enablements
    user_repo_pairs = T.let([], T::Array[{ user_id: Integer, repo_id: Integer, pushed_at: Time }])
    licenses.each do |license|
      licensee = license.licensee
      next if licensee.nil?
      next if licensee.type == :LICENSEE_TYPE_ENTERPRISE_SERVER_USER
      next if license.expiresAt.present? && T.must(license.expiresAt).to_time < now

      user_id = licensee.id.to_i

      license.enablements.each do |enablement|
        next unless enablement.reason == :ENABLEMENT_REASON_REPOSITORY_COMMITTER

        enablement.enablementIds.each do |enablement_id|
          repo_id_str, pushed_at_str = enablement_id.split(":", 2)
          next if repo_id_str.blank?

          pushed_at_time = begin
            if pushed_at_str.present?
              Date.parse(pushed_at_str).to_time(:utc)
            else
              Time.at(0).utc
            end
          rescue ArgumentError, TypeError
            Time.at(0).utc
          end

          user_repo_pairs << { user_id: user_id, repo_id: repo_id_str.to_i, pushed_at: pushed_at_time }
        end
      end
    end

    # Filter by repository_ids if provided, before DB lookups for efficiency
    if repository_ids.present?
      repo_id_set = repository_ids.to_set
      user_repo_pairs.select! { |p| repo_id_set.include?(p[:repo_id]) }
    end

    # Batch-lookup repository NWOs — mirrors VariantAnalysis::RepositoryResolutionHelper#resolve_repo_nwos_from_ids
    # but tolerates missing repos (skips them) instead of raising.
    repo_ids = user_repo_pairs.map { |p| p[:repo_id] }.uniq
    nwos_by_id = repo_ids.each_slice(5000).each_with_object({}) do |ids, result|
      Repositories.domain.by_ids(T.let(ids, T::Array[Integer]))
        .pluck(:id, :name, :owner_login)
        .each { |id, name, owner_login| result[id] = "#{User.to_display_login(owner_login)}/#{name}" }
    end

    # Batch-lookup users for logins and emails
    user_ids = user_repo_pairs.map { |p| p[:user_id] }.uniq
    users_by_id = user_ids.each_slice(5000).each_with_object({}) do |ids, result|
      User.where(id: ids).includes(:primary_user_email, :stealth_user_email, :profile, :primary_private_user_email).each do |user|
        result[user.id] = user
      end
    end

    # Convert into Turboghas::Proto::GetCommittersResponse::Committer
    # so the rest of the pipeline (CSV, JSON generation) works unchanged.
    user_repo_pairs.filter_map do |pair|
      nwo = nwos_by_id[pair[:repo_id]]
      next if nwo.nil?

      user = users_by_id[pair[:user_id]]
      next if user.nil?

      ::Turboghas::Proto::GetCommittersResponse::Committer.new(
        id: user.id,
        login: user.display_login,
        email: user.git_author_email,
        repository_id: pair[:repo_id],
        repository_nwo: nwo,
        pushed_at: Google::Protobuf::Timestamp.new(seconds: pair[:pushed_at].to_i),
      )
    end
  end

  # Format a pushed_at Timestamp for display. Returns "-" if the date is unknown (epoch).
  sig { params(pushed_at: T.nilable(Google::Protobuf::Timestamp)).returns(String) }
  def self.format_pushed_at(pushed_at)
    time = T.must(pushed_at).to_time.utc
    time.to_i == 0 ? "-" : time.strftime("%Y-%m-%d")
  end

  sig do
    params(
      entity: T.any(User, Business, Organization),
      committer_type: Symbol,
      repository_ids: T.nilable(T::Array[Integer]),
      sku: GitHub::Turboghas::SKU,
    ).returns(String)
  end
  def self.generate_csv(entity:, committer_type: :ACTIVE_COMMITTERS, repository_ids: nil, sku: GitHub::Turboghas::SKU::Bundled)
    CSV.generate do |csv|
      csv << Business::AdvancedSecurityCommittersGenerator::HEADERS
      get_committers(entity, committer_type: committer_type, repository_ids: repository_ids, sku:).each do |row|
        csv << [row.display_login, row.name_with_display_owner, format_pushed_at(row.pushed_at), row.email]
      end
    end
  end

  # generate the data used by the api json output
  sig do
    params(
      owner: T.any(User, Business, Organization),
      page: Integer,
      per_page: Integer,
      committer_type: Symbol,
      repository_ids: T.nilable(T::Array[Integer]),
      sku: GitHub::Turboghas::SKU,
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def self.generate_json(owner, page: 1, per_page: 30, committer_type: :ACTIVE_COMMITTERS, repository_ids: nil, sku: GitHub::Turboghas::SKU::Bundled)
    by_repository = get_committers(owner, committer_type:, repository_ids:, sku:).group_by(&:name_with_display_owner)

    repository_nwos = if owner.advanced_security_purchased?
      by_repository.keys
    else
      []
    end

    # the total number of repositories with advanced security enabled
    total_count = repository_nwos.size

    license_info = if owner.advanced_security_billable_entity?
      summary =  AdvancedSecurityLicense.summary(entity: owner, sku:)

      {
        total_advanced_security_committers: summary.active_committers,
        maximum_advanced_security_committers: summary.maximum_committers,
        purchased_advanced_security_committers: (owner.advanced_security_license.seats if owner.advanced_security_license.seats.nonzero?)
      }.compact
    else
      {
        total_advanced_security_committers: owner.advanced_security_seats_used(sku:),
      }
    end

    distinct_users = Set.new

    paged_repository_nwos = repository_nwos.slice((page - 1) * per_page, per_page)

    items = T.unsafe(by_repository).slice(*paged_repository_nwos).map do |repository_nwo, rows|
      { name: repository_nwo, advanced_security_committers: 0, advanced_security_committers_breakdown: [] }.tap do |breakdown|
        rows.each do |row|
          distinct_users.add(row.id)
          breakdown[:advanced_security_committers] += 1
          breakdown[:advanced_security_committers_breakdown] << {
            user_login: row.display_login,
            last_pushed_date: format_pushed_at(row.pushed_at),
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

  sig do
    params(
      entity: T.any(User, Business, Organization),
      limit: T.nilable(Integer),
      cursor: T.untyped,
      committer_type: Symbol,
      repository_ids: T.nilable(T::Array[Integer]),
      sku: GitHub::Turboghas::SKU,
      attempted_retries: Integer,
    ).returns(::Turboghas::Proto::GetCommittersResponse)
  end
  def self.get_committers_paginated(entity, limit: nil, cursor: nil, committer_type: :ACTIVE_COMMITTERS, repository_ids: nil, sku: GitHub::Turboghas::SKU::Bundled, attempted_retries: 0)
    return ::Turboghas::Proto::GetCommittersResponse.new if entity.nil?

    # Don't make tests slow
    unless Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      sleep attempted_retries**2
    end

    features = sku.features

    # support overriding the timeout in Stafftools when downloading very large CSVs
    patient_client = GitHub::Turboghas.new_client(connection: GitHub::Turboghas.connection(timeout: 10))

    if entity.is_a?(User)
      response = patient_client.get_committers_for_owner(Turboghas::Proto::GetCommittersForOwnerRequest.new(
        owner_id: entity.id, limit:, cursor:, committer_type:, repository_ids:, features:
      ))
    else
      response = patient_client.get_committers_for_business(Turboghas::Proto::GetCommittersForBusinessRequest.new(
        business_id: entity.id, limit:, cursor:, committer_type:, repository_ids:, features:
      ))
    end

    unless response.error.nil?
      error_message = T.must(response.error).msg

      if error_message == "unavailable" && attempted_retries < GET_COMMITTERS_PAGINATED_RETRIES
        return get_committers_paginated(entity, limit:, cursor:, committer_type:, repository_ids:, sku:, attempted_retries: attempted_retries + 1)
      end

      e = ::GitHub::Turboghas::ResponseError.new(error_message)
      Failbot.report(e, catalog_service: "github/licensing")
      raise e
    end
    response.data
  end
end
