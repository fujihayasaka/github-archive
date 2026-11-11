# typed: strict
# frozen_string_literal: true

require "set"

module Business::AdvancedSecurityCommittersGenerator
  class EntityNotBillableError < ArgumentError; end
  GET_COMMITTERS_MAX_PAGE_SIZE = 200000
  HEADERS = ["User login", "Organization / repository", "Last pushed date", "Last pushed email"].freeze
  GET_COMMITTERS_PAGINATED_RETRIES = 3
  LICENSIFY_CUSTOMER_LICENSES_PAGE_SIZE = 5000

  sig { params(entity: T.any(User, Business, Organization), committer_type: Symbol).returns(Symbol) }
  def self.committers_source(entity, committer_type)
    customer_id = Licensing::Customer.id_for(entity)
    uses_licensify =
      !GitHub.enterprise? &&
      committer_type == :ACTIVE_COMMITTERS &&
      customer_id.present? &&
      !organization_owned_by_enterprise?(entity)

    if uses_licensify
      :licensify
    else
      :turboghas
    end
  end

  sig { params(entity: T.any(User, Business, Organization)).returns(T::Boolean) }
  def self.organization_owned_by_enterprise?(entity)
    entity.is_a?(Organization) && entity.business_membership.present?
  end

  sig { params(entity: T.any(User, Business, Organization)).returns(String) }
  def self.entity_type_tag(entity)
    case entity
    when Business then "business"
    when Organization then "organization"
    else "user"
    end
  end

  sig { params(committer_type: Symbol).returns(String) }
  def self.committer_type_tag(committer_type)
    committer_type.to_s.downcase
  end

  sig { params(mode: String, source: Symbol, entity: T.any(User, Business, Organization), committer_type: Symbol, sku: GitHub::Turboghas::SKU).returns(T::Array[String]) }
  def self.export_metric_tags(mode:, source:, entity:, committer_type:, sku:)
    [
      "mode:#{mode}",
      "source:#{source}",
      "entity_type:#{entity_type_tag(entity)}",
      "committer_type:#{committer_type_tag(committer_type)}",
      "sku:#{sku.to_param}",
    ]
  end

  sig do
    params(
      entity: T.any(User, Business, Organization),
      committer_type: Symbol,
      repository_ids: T.nilable(T::Array[Integer]),
      sku: GitHub::Turboghas::SKU,
      blk: T.proc.params(committer: ::Turboghas::Proto::GetCommittersResponse::Committer).void,
    ).void
  end
  def self.each_committer(entity, committer_type: :ACTIVE_COMMITTERS, repository_ids: nil, sku: GitHub::Turboghas::SKU::Bundled, &blk)
    if committers_source(entity, committer_type) == :licensify
      each_committer_from_licensify(entity, sku: sku, repository_ids: repository_ids, &blk)
      return
    end

    data = get_committers_paginated(entity, limit: GET_COMMITTERS_MAX_PAGE_SIZE, committer_type:, repository_ids:, sku:)
    loop do
      data.committers.each(&blk)
      break if data.next_cursor.blank?

      data = get_committers_paginated(entity, limit: GET_COMMITTERS_MAX_PAGE_SIZE, cursor: data.next_cursor, committer_type:, repository_ids:, sku:)
    end
  end

  sig do
    params(
      entity: T.any(User, Business, Organization),
      committer_type: Symbol,
      repository_ids: T.nilable(T::Array[Integer]),
      sku: GitHub::Turboghas::SKU,
    ).returns(T::Array[::Turboghas::Proto::GetCommittersResponse::Committer])
  end
  def self.get_committers(entity, committer_type: :ACTIVE_COMMITTERS, repository_ids: nil, sku: GitHub::Turboghas::SKU::Bundled)
    if committers_source(entity, committer_type) == :licensify
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

    if FeatureFlag.vexi.enabled?(:ghas_committers_incremental_hydration, entity, default: false)
      # Delegate to the streaming path which processes Licensify pages incrementally,
      # caching hydrated repos/users across pages so only new IDs trigger DB lookups.
      # Collect results into an array since callers (generate_csv, generate_json)
      # expect fully materialized data.
      committers = T.let([], T::Array[::Turboghas::Proto::GetCommittersResponse::Committer])
      each_committer_from_licensify(entity, sku: sku, repository_ids: repository_ids) do |committer|
        committers << committer
      end
      return committers
    end

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
      expires_at = license.expiresAt
      next if licensee.nil?
      next if licensee.type == :LICENSEE_TYPE_ENTERPRISE_SERVER_USER
      next if expires_at.present? && expires_at.to_time < now

      user_id = licensee.id.to_i

      license.enablements.each do |enablement|
        next unless enablement.reason == :ENABLEMENT_REASON_REPOSITORY_COMMITTER

        enablement.enablementIds.each do |enablement_id|
          repo_id_str, pushed_at_str = enablement_id.split(":", 2)
          next if repo_id_str.blank?

          pushed_at_time = parse_pushed_at(pushed_at_str)
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
    nwos_by_id = Repository.active.batched_scope(:id, values: repo_ids, batch_size: 5000)
      .pluck(:id, :name, :owner_login)
      .each_with_object({}) { |(id, name, owner_login), result| result[id] = "#{User.to_display_login(owner_login)}/#{name}" }

    # Batch-lookup users for logins and emails
    user_ids = user_repo_pairs.map { |p| p[:user_id] }.uniq
    users_scope = User.batched_scope(:id, values: user_ids, batch_size: 5000) do |scope|
      scope.select(:id, :login, :display_login, :type, :business_id)
        .includes(:primary_user_email, :stealth_user_email, :profile, :primary_private_user_email)
    end
    users_by_id = users_scope.to_a.index_by(&:id)

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

  sig do
    params(
      entity: T.any(User, Business, Organization),
      sku: GitHub::Turboghas::SKU,
      repository_ids: T.nilable(T::Array[Integer]),
      blk: T.proc.params(committer: ::Turboghas::Proto::GetCommittersResponse::Committer).void,
    ).void
  end
  def self.each_committer_from_licensify(entity, sku: GitHub::Turboghas::SKU::Bundled, repository_ids: nil, &blk)
    GitHub.logger.info(
      "each_committer_from_licensify called",
      "code.namespace" => "Business::AdvancedSecurityCommittersGenerator",
      "code.function" => "each_committer_from_licensify",
      "gh.licensing.get_committers_from_licensify.repository_count" => repository_ids&.size || 0
    )

    customer_id = Licensing::Customer.id_for(entity)
    return if customer_id.nil?

    product = Licensing::Licensify::LicensifyProduct.from_turboghas_sku(sku)

    # Expand customer licenses into per-user, per-repo pairs from enablements.
    # Enablements with REPO-type enablementIds contain strings in the format "REPO_ID:PUSHED_AT".
    # Skip licenses that are still marked "active" but have already expired (billing
    # keeps them active through the end of the month).
    now = Time.now.utc
    repo_id_filter = repository_ids&.to_set
    nwos_by_id = T.let({}, T::Hash[Integer, String])
    users_by_id = T.let({}, T::Hash[Integer, User])

    offset = 0
    page_number = 0
    total_licenses = T.let(0, Integer)
    begin
      loop do
        page_number += 1
        page_started_at = GitHub::Dogstats.monotonic_time

        response = Licensing.get_customer_licenses(
          customer_id,
          product: product,
          statuses: [::Licensify::Services::V1::LicenseStatus::LICENSE_STATUS_ACTIVE],
          limit: LICENSIFY_CUSTOMER_LICENSES_PAGE_SIZE,
          offset: offset,
        )
        total_licenses = response.total
        licensify_duration_ms = GitHub::Dogstats.duration(page_started_at)

        page_pairs = T.let([], T::Array[{ user_id: Integer, repo_id: Integer, pushed_at: Time }])
        page_repo_ids = T.let(Set.new, T::Set[Integer])
        page_user_ids = T.let(Set.new, T::Set[Integer])

        response.customerLicenses.each do |license|
          licensee = license.licensee
          expires_at = license.expiresAt
          next if licensee.nil?
          next if licensee.type == :LICENSEE_TYPE_ENTERPRISE_SERVER_USER
          next if expires_at.present? && expires_at.to_time < now

          user_id = licensee.id.to_i

          license.enablements.each do |enablement|
            next unless enablement.reason == :ENABLEMENT_REASON_REPOSITORY_COMMITTER

            enablement.enablementIds.each do |enablement_id|
              repo_id_str, pushed_at_str = enablement_id.split(":", 2)
              next if repo_id_str.blank?

              repo_id = repo_id_str.to_i
              next if repo_id_filter.present? && !repo_id_filter.include?(repo_id)

              page_pairs << {
                user_id: user_id,
                repo_id: repo_id,
                pushed_at: parse_pushed_at(pushed_at_str),
              }
              page_repo_ids.add(repo_id)
              page_user_ids.add(user_id)
            end
          end
        end

        new_repo_count = page_repo_ids.count { |id| !nwos_by_id.key?(id) }
        new_user_count = page_user_ids.count { |id| !users_by_id.key?(id) }

        hydrate_started_at = GitHub::Dogstats.monotonic_time
        hydrate_repo_nwos(nwos_by_id, page_repo_ids)
        hydrate_users(users_by_id, page_user_ids)
        hydrate_duration_ms = GitHub::Dogstats.duration(hydrate_started_at)

        page_pairs.each do |pair|
          nwo = nwos_by_id[pair[:repo_id]]
          next if nwo.nil?

          user = users_by_id[pair[:user_id]]
          next if user.nil?

          blk.call(::Turboghas::Proto::GetCommittersResponse::Committer.new(
            id: user.id,
            login: user.display_login,
            email: user.git_author_email,
            repository_id: pair[:repo_id],
            repository_nwo: nwo,
            pushed_at: Google::Protobuf::Timestamp.new(seconds: pair[:pushed_at].to_i),
          ))
        end

        page_duration_ms = GitHub::Dogstats.duration(page_started_at)
        total_pages = [(total_licenses.to_f / LICENSIFY_CUSTOMER_LICENSES_PAGE_SIZE).ceil, 1].max

        GitHub.logger.info(
          "GHAS committers Licensify page complete",
          "code.namespace" => "Business::AdvancedSecurityCommittersGenerator",
          "code.function" => "each_committer_from_licensify",
          "gh.customer.id" => customer_id,
          "gh.entity.type" => entity_type_tag(entity),
          "gh.entity.id" => entity.id,
          "gh.entity.slug" => entity.try(:slug) || entity.try(:login),
          "gh.advanced_security.committers.page_number" => page_number,
          "gh.advanced_security.committers.total_pages" => total_pages,
          "gh.advanced_security.committers.total_licenses" => total_licenses,
          "gh.advanced_security.committers.page_licenses" => response.customerLicenses.size,
          "gh.advanced_security.committers.page_pairs" => page_pairs.size,
          "gh.advanced_security.committers.page_new_repos" => new_repo_count,
          "gh.advanced_security.committers.page_new_users" => new_user_count,
          "gh.advanced_security.committers.cached_repos" => nwos_by_id.size,
          "gh.advanced_security.committers.cached_users" => users_by_id.size,
          "gh.advanced_security.committers.licensify_duration_ms" => licensify_duration_ms,
          "gh.advanced_security.committers.hydrate_duration_ms" => hydrate_duration_ms,
          "gh.advanced_security.committers.page_duration_ms" => page_duration_ms,
        )
        page_metric_tags = export_metric_tags(mode: "stream", source: :licensify, entity: entity, committer_type: :ACTIVE_COMMITTERS, sku: sku)
        GitHub.dogstats.distribution("advanced_security.committers_export.licensify_page_duration_ms", page_duration_ms, tags: page_metric_tags)
        GitHub.dogstats.distribution("advanced_security.committers_export.licensify_api_duration_ms", licensify_duration_ms, tags: page_metric_tags)
        GitHub.dogstats.distribution("advanced_security.committers_export.licensify_hydrate_duration_ms", hydrate_duration_ms, tags: page_metric_tags)

        offset += LICENSIFY_CUSTOMER_LICENSES_PAGE_SIZE
        break if offset >= response.total
      end
    rescue Licensing::Licensify::LicensifyRequestFailed => e
      Failbot.report(e, catalog_service: "github/licensing")
      raise e
    end
  end

  sig { params(pushed_at: T.nilable(String)).returns(Time) }
  def self.parse_pushed_at(pushed_at)
    return Time.at(0).utc if pushed_at.blank?

    Date.parse(pushed_at).to_time(:utc)
  rescue ArgumentError, TypeError
    Time.at(0).utc
  end

  sig { params(nwos_by_id: T::Hash[Integer, String], repo_ids: T::Set[Integer]).void }
  def self.hydrate_repo_nwos(nwos_by_id, repo_ids)
    missing_repo_ids = repo_ids.reject { |id| nwos_by_id.key?(id) }
    return if missing_repo_ids.empty?

    Repository.active.batched_scope(:id, values: missing_repo_ids.to_a, batch_size: 5000)
      .pluck(:id, :name, :owner_login)
      .each { |id, name, owner_login| nwos_by_id[id] = "#{User.to_display_login(owner_login)}/#{name}" }
  end

  sig { params(users_by_id: T::Hash[Integer, User], user_ids: T::Set[Integer]).void }
  def self.hydrate_users(users_by_id, user_ids)
    missing_user_ids = user_ids.reject { |id| users_by_id.key?(id) }
    return if missing_user_ids.empty?

    batched_users = User.batched_scope(:id, values: missing_user_ids.to_a, batch_size: 5000) do |scope|
      scope.select(:id, :login, :display_login, :type, :business_id)
        .includes(:primary_user_email, :stealth_user_email, :profile, :primary_private_user_email)
    end

    batched_users.each do |user|
      users_by_id[user.id] = user
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
    started_at = GitHub::Dogstats.monotonic_time
    source = committers_source(entity, committer_type)
    tags = export_metric_tags(mode: "legacy", source:, entity:, committer_type:, sku:)

    row_count = 0
    CSV.generate do |csv|
      csv << Business::AdvancedSecurityCommittersGenerator::HEADERS
      get_committers(entity, committer_type: committer_type, repository_ids: repository_ids, sku:).each do |row|
        row_count += 1
        csv << [row.display_login, row.name_with_display_owner, format_pushed_at(row.pushed_at), row.email]
      end
    end.tap do |_csv|
      GitHub.dogstats.distribution("advanced_security.committers_export.duration_ms", GitHub::Dogstats.duration(started_at), tags: tags)
      GitHub.dogstats.distribution("advanced_security.committers_export.rows", row_count, tags: tags)
      GitHub.dogstats.increment("advanced_security.committers_export.completed", tags: tags)
    end
  end

  sig do
    params(
      entity: T.any(User, Business, Organization),
      committer_type: Symbol,
      repository_ids: T.nilable(T::Array[Integer]),
      sku: GitHub::Turboghas::SKU,
    ).returns(T::Enumerator[String])
  end
  def self.generate_csv_enumerator(entity:, committer_type: :ACTIVE_COMMITTERS, repository_ids: nil, sku: GitHub::Turboghas::SKU::Bundled)
    started_at = GitHub::Dogstats.monotonic_time
    source = committers_source(entity, committer_type)
    tags = export_metric_tags(mode: "stream", source:, entity:, committer_type:, sku:)

    Enumerator.new do |output|
      first_chunk_sent = T.let(false, T::Boolean)
      failed = T.let(false, T::Boolean)
      aborted = T.let(false, T::Boolean)

      emit_first_chunk_timing = lambda do
        next if first_chunk_sent

        first_chunk_sent = true
        GitHub.dogstats.distribution("advanced_security.committers_export.ttfb_ms", GitHub::Dogstats.duration(started_at), tags: tags)
      end

      row_count = 0
      begin
        output << CSV.generate_line(Business::AdvancedSecurityCommittersGenerator::HEADERS)
        emit_first_chunk_timing.call
        each_committer(entity, committer_type:, repository_ids:, sku:) do |row|
          row_count += 1
          output << CSV.generate_line([row.display_login, row.name_with_display_owner, format_pushed_at(row.pushed_at), row.email])
        end
      rescue StandardError => e
        if streaming_disconnect_error?(e)
          aborted = true
          GitHub.dogstats.increment("advanced_security.committers_export.aborted", tags: tags)
        else
          failed = true
          GitHub.dogstats.increment("advanced_security.committers_export.failed", tags: tags)
          raise
        end
      ensure
        GitHub.dogstats.distribution("advanced_security.committers_export.duration_ms", GitHub::Dogstats.duration(started_at), tags: tags)
        GitHub.dogstats.distribution("advanced_security.committers_export.rows", row_count, tags: tags)
        GitHub.dogstats.increment("advanced_security.committers_export.completed", tags: tags) unless failed || aborted
      end
    end
  end

  sig { params(error: StandardError).returns(T::Boolean) }
  def self.streaming_disconnect_error?(error)
    return true if error.is_a?(IOError) || error.is_a?(Errno::EPIPE) || error.is_a?(Errno::ECONNRESET)
    return true if defined?(ActionController::Live::ClientDisconnected) && error.is_a?(ActionController::Live::ClientDisconnected)

    false
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
    # When the data source is Licensify and the paginated-JSON flag is enabled,
    # take the page-aware path that avoids loading all repos/users for the
    # entire enterprise into memory before slicing.
    if committers_source(owner, committer_type) == :licensify &&
        FeatureFlag.vexi.enabled?(:ghas_committers_paginated_json, owner, default: false)
      return generate_paginated_json_from_licensify(
        owner,
        page: page,
        per_page: per_page,
        repository_ids: repository_ids,
        sku: sku,
      )
    end

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

  # Page-aware JSON generation for the Licensify data source.
  #
  # The legacy `generate_json` path materializes every committer for the entire
  # entity (and hydrates every distinct Repository / User) before slicing the
  # requested page. For large enterprises that reliably exceeds the API
  # timeout, even when the caller asks for `per_page=1`.
  #
  # This implementation runs in two passes:
  #   1. Scan Licensify and accumulate `{user_id, pushed_at}` pairs grouped by
  #      `repo_id`. No DB hydration during the scan.
  #   2. Cheaply pre-validate which `repo_id`s and `user_id`s exist (single
  #      column index plucks), determine the page slice in first-seen order,
  #      then hydrate full Repository NWOs and User records only for the
  #      repositories on the requested page.
  sig do
    params(
      owner: T.any(User, Business, Organization),
      page: Integer,
      per_page: Integer,
      repository_ids: T.nilable(T::Array[Integer]),
      sku: GitHub::Turboghas::SKU,
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def self.generate_paginated_json_from_licensify(owner, page:, per_page:, repository_ids: nil, sku: GitHub::Turboghas::SKU::Bundled)
    pairs_by_repo = T.let({}, T::Hash[Integer, T::Array[{ user_id: Integer, pushed_at: Time }]])
    repo_order = T.let([], T::Array[Integer])
    repo_seen = T.let(Set.new, T::Set[Integer])
    all_user_ids = T.let(Set.new, T::Set[Integer])

    # Pass 1: stream Licensify without DB hydration.
    each_committer_pair_from_licensify(owner, sku: sku, repository_ids: repository_ids) do |repo_id, user_id, pushed_at|
      unless repo_seen.include?(repo_id)
        repo_seen.add(repo_id)
        repo_order << repo_id
      end
      (pairs_by_repo[repo_id] ||= []) << { user_id: user_id, pushed_at: pushed_at }
      all_user_ids.add(user_id)
    end

    # Cheap pre-validation: pluck just IDs to filter out repos/users that no
    # longer exist (or are no longer active). Mirrors the implicit filtering
    # the legacy path performed via `hydrate_repo_nwos` / `hydrate_users`.
    surviving_repo_ids = T.let([], T::Array[Integer])
    if owner.advanced_security_purchased? && !repo_order.empty?
      existing_repo_ids = pluck_existing_repo_ids(repo_order)
      existing_user_ids = pluck_existing_user_ids(all_user_ids.to_a)

      surviving_repo_ids = repo_order.select do |rid|
        next false unless existing_repo_ids.include?(rid)

        T.must(pairs_by_repo[rid]).any? { |p| existing_user_ids.include?(p[:user_id]) }
      end
    end

    total_count = surviving_repo_ids.size

    # License info — capture `summary` so we can reuse it below instead of
    # issuing a second `get_summary` Turboghas RPC for non-first pages.
    summary = T.let(nil, T.nilable(::Turboghas::Proto::GetSummaryResponse))
    license_info = T.let({}, T::Hash[Symbol, T.untyped])
    if owner.advanced_security_billable_entity?
      summary = AdvancedSecurityLicense.summary(entity: owner, sku: sku)

      license_info[:maximum_advanced_security_committers] = summary.maximum_committers
      seats = owner.advanced_security_license.seats
      license_info[:purchased_advanced_security_committers] = seats if seats.nonzero?
    end

    page_repo_ids = surviving_repo_ids.slice((page - 1) * per_page, per_page) || []

    # Pass 2: hydrate NWOs and Users for just the repos on this page.
    nwos_by_id = T.let({}, T::Hash[Integer, String])
    users_by_id = T.let({}, T::Hash[Integer, User])
    if !page_repo_ids.empty?
      hydrate_repo_nwos(nwos_by_id, page_repo_ids.to_set)
      page_user_ids = T.let(Set.new, T::Set[Integer])
      page_repo_ids.each do |rid|
        T.must(pairs_by_repo[rid]).each { |p| page_user_ids.add(p[:user_id]) }
      end
      hydrate_users(users_by_id, page_user_ids)
    end

    distinct_users = Set.new

    items = page_repo_ids.filter_map do |repo_id|
      nwo = nwos_by_id[repo_id]
      next if nwo.nil?

      breakdown = { name: nwo, advanced_security_committers: 0, advanced_security_committers_breakdown: [] }
      T.must(pairs_by_repo[repo_id]).each do |pair|
        user = users_by_id[pair[:user_id]]
        next if user.nil?

        distinct_users.add(user.id)
        breakdown[:advanced_security_committers] += 1
        breakdown[:advanced_security_committers_breakdown] << {
          user_login: user.display_login,
          last_pushed_date: format_pushed_at(Google::Protobuf::Timestamp.new(seconds: pair[:pushed_at].to_i)),
          last_pushed_email: user.git_author_email,
        }
      end
      breakdown
    end

    more_repos = per_page * page < total_count

    total_advanced_security_committers = if !more_repos && page == 1
      distinct_users.size
    elsif summary
      # Reuse the summary we already fetched above instead of issuing a second
      # Turboghas `get_summary` RPC.
      summary.active_committers
    else
      owner.advanced_security_seats_used(sku: sku)
    end

    {
      repositories: items,
      total_count: total_count,
      **license_info,
      # Intentionally placed after `**license_info` so the computed value wins.
      # The legacy `generate_json` path puts the splat last, which causes
      # `license_info[:total_advanced_security_committers]` to clobber the
      # `distinct_users.size` branch — making that branch dead code. Here we
      # honor the original intent: when we have complete first-page data with
      # no more pages, return the exact distinct-user count; otherwise fall
      # back to the summary (preferred) or seats_used.
      total_advanced_security_committers: total_advanced_security_committers,
    }
  end

  # Like `each_committer_from_licensify`, but yields lightweight
  # `(repo_id, user_id, pushed_at)` triples without hydrating Repository or
  # User records. Intended for callers that only need to know the structural
  # set of (repo, user) pairs before deciding which subset to hydrate.
  sig do
    params(
      entity: T.any(User, Business, Organization),
      sku: GitHub::Turboghas::SKU,
      repository_ids: T.nilable(T::Array[Integer]),
      blk: T.proc.params(repo_id: Integer, user_id: Integer, pushed_at: Time).void,
    ).void
  end
  def self.each_committer_pair_from_licensify(entity, sku: GitHub::Turboghas::SKU::Bundled, repository_ids: nil, &blk)
    customer_id = Licensing::Customer.id_for(entity)
    return if customer_id.nil?

    product = Licensing::Licensify::LicensifyProduct.from_turboghas_sku(sku)
    now = Time.now.utc
    repo_id_filter = repository_ids&.to_set

    offset = 0
    page_number = 0
    total_licenses = T.let(0, Integer)
    metric_tags = export_metric_tags(mode: "paginated_json", source: :licensify, entity: entity, committer_type: :ACTIVE_COMMITTERS, sku: sku)

    begin
      loop do
        page_number += 1
        page_started_at = GitHub::Dogstats.monotonic_time
        page_pair_count = 0

        response = Licensing.get_customer_licenses(
          customer_id,
          product: product,
          statuses: [::Licensify::Services::V1::LicenseStatus::LICENSE_STATUS_ACTIVE],
          limit: LICENSIFY_CUSTOMER_LICENSES_PAGE_SIZE,
          offset: offset,
        )
        total_licenses = response.total
        licensify_duration_ms = GitHub::Dogstats.duration(page_started_at)

        response.customerLicenses.each do |license|
          licensee = license.licensee
          expires_at = license.expiresAt
          next if licensee.nil?
          next if licensee.type == :LICENSEE_TYPE_ENTERPRISE_SERVER_USER
          next if expires_at.present? && expires_at.to_time < now

          user_id = licensee.id.to_i

          license.enablements.each do |enablement|
            next unless enablement.reason == :ENABLEMENT_REASON_REPOSITORY_COMMITTER

            enablement.enablementIds.each do |enablement_id|
              repo_id_str, pushed_at_str = enablement_id.split(":", 2)
              next if repo_id_str.blank?

              repo_id = repo_id_str.to_i
              next if repo_id_filter.present? && !repo_id_filter.include?(repo_id)

              page_pair_count += 1
              blk.call(repo_id, user_id, parse_pushed_at(pushed_at_str))
            end
          end
        end

        page_duration_ms = GitHub::Dogstats.duration(page_started_at)
        total_pages = [(total_licenses.to_f / LICENSIFY_CUSTOMER_LICENSES_PAGE_SIZE).ceil, 1].max

        GitHub.logger.info(
          "GHAS committers Licensify paginated-json page complete",
          "code.namespace" => "Business::AdvancedSecurityCommittersGenerator",
          "code.function" => "each_committer_pair_from_licensify",
          "gh.customer.id" => customer_id,
          "gh.entity.type" => entity_type_tag(entity),
          "gh.entity.id" => entity.id,
          "gh.entity.slug" => entity.try(:slug) || entity.try(:login),
          "gh.advanced_security.committers.page_number" => page_number,
          "gh.advanced_security.committers.total_pages" => total_pages,
          "gh.advanced_security.committers.total_licenses" => total_licenses,
          "gh.advanced_security.committers.page_licenses" => response.customerLicenses.size,
          "gh.advanced_security.committers.page_pairs" => page_pair_count,
          "gh.advanced_security.committers.licensify_duration_ms" => licensify_duration_ms,
          "gh.advanced_security.committers.page_duration_ms" => page_duration_ms,
        )
        GitHub.dogstats.distribution("advanced_security.committers_export.licensify_page_duration_ms", page_duration_ms, tags: metric_tags)
        GitHub.dogstats.distribution("advanced_security.committers_export.licensify_api_duration_ms", licensify_duration_ms, tags: metric_tags)

        offset += LICENSIFY_CUSTOMER_LICENSES_PAGE_SIZE
        break if offset >= response.total
      end
    rescue Licensing::Licensify::LicensifyRequestFailed => e
      Failbot.report(e, catalog_service: "github/licensing")
      raise e
    end
  end

  # Cheap pluck of just `id` for active repositories, batched. Used for
  # pagination pre-validation to filter out deleted/inactive repos without
  # paying the cost of a full NWO hydration.
  sig { params(repo_ids: T::Array[Integer]).returns(T::Set[Integer]) }
  def self.pluck_existing_repo_ids(repo_ids)
    return Set.new if repo_ids.empty?

    result = T.let(Set.new, T::Set[Integer])
    Repository.active.batched_scope(:id, values: repo_ids, batch_size: 5000)
      .pluck(:id)
      .each { |id| result.add(id) }
    result
  end

  # Cheap pluck of just `id` for users, batched. Used for pagination
  # pre-validation. Note: full User hydration (with email associations) still
  # happens later for the page slice in `hydrate_users`.
  sig { params(user_ids: T::Array[Integer]).returns(T::Set[Integer]) }
  def self.pluck_existing_user_ids(user_ids)
    return Set.new if user_ids.empty?

    result = T.let(Set.new, T::Set[Integer])
    user_ids.each_slice(5000) do |ids|
      User.where(id: ids).pluck(:id).each { |id| result.add(id) }
    end
    result
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
