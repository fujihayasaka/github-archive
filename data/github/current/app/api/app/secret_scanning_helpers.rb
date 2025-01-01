# typed: true
# frozen_string_literal: true

module Api::App::SecretScanningHelpers
  extend T::Helpers
  include GitHub::SecurityCenter::TenantFilteringHelper
  include GitHub::TokenScanning::SecretScanningHelper
  include GitHub::TokenScanning::TokenScanningPostProcessingHelper
  include SecretScanning::Encryption::EncryptedSecretsHelper
  include SecretScanning::Errors
  include SecretScanning::Features::FeatureFlagHelper

  abstract!

  requires_ancestor { Api::App::ErrorDependency }

  attr_accessor :location_blobs

  # Checks whether alerts APIs can be accessed on the repo.
  def validate_repository_access_for_alerts_apis(repo)
    # Secret scanning needs to be enabled on the repo.
    deliver_error!(404, message: "Secret scanning is disabled on this repository.") unless SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
  end

  # Checks whether the repository has purchased secret scanning
  def validate_secret_scanning_purchased(repo)
    owner = repo.owner
    return unless owner

    # Checks are mostly separated to ensure the user gets a good error back.
    if owner.advanced_security_products_bundled?
      deliver_error!(404, message: "Advanced Security is disabled on this repository.") unless repo.advanced_security_enabled?
    else
      available = SecretScanning::Features::AdvancedSecurityHelper.secret_scanning_available?(repo)
      deliver_error!(404, message: "Secret Protection is disabled on this repository.") unless available
    end
  end

  # Find and return an alert
  def find_alert_by_number(repo, alert_number, multiline_secret_with_newline: false)
    response = GitHub::TokenScanning::Service::Client.new(current_user).get_token(
      repository_id: repo.id,
      token_id: alert_number,
      feature_flags: get_tokens_api_feature_flags(repo),
    )

    deliver_error!(503, message: "Secret scanning unavailable. Please try again later.") if response.nil?

    if response.error && response.error&.code != :not_found
      Failbot.report(
        StandardError.new("Unable to retrieve secret scanning alert"),
        repo_id: repo.id,
        alert_number: alert_number,
        error_code: response.error&.code,
        error_message: response.error&.msg,
      )
      deliver_error!(500, message: "Error finding secret scanning alert.")
    end

    result = response.data&.token
    return nil if result.nil?

    # Build alert with secret
    alert = GitHub::TokenScanning::Service::Client.wrap_token(result, repo)
    set_raw_secret_from_encrypted_secret(alert)
    if alert.raw_secret.nil?
      SecretScanning::Util::RawSecret.replacement_for_nil_raw_secret(alert)
    end
    alert
  end

  # Find and return an alert with associated token scan locations
  def find_alert_with_locations(repo, alert_number, page_size, current_page)
    response = GitHub::TokenScanning::Service::Client.new(current_user).get_token(
      repository_id: repo.id,
      token_id: alert_number,
      include_included_locations: true,
      include_location_count: true,
      limit: page_size,
      page: current_page,
      feature_flags: get_tokens_api_feature_flags(repo),
    )

    deliver_error!(503, message: "Secret scanning unavailable. Please try again later.") if response.nil?

    if response.error && response.error&.code != :not_found
      Failbot.report(
        StandardError.new("Unable to retrieve secret scanning alert"),
        repo_id: repo.id,
        alert_number: alert_number,
        error_code: response.error&.code,
        error_message: response.error&.msg,
      )
      deliver_error!(500, message: "Error finding secret scanning alert.")
    end

    result = response.data&.token
    return nil if result.nil?
    GitHub::TokenScanning::Service::Client.wrap_token(result, repo, response.data)
  end

  def sort_newest_first(alerts)
    return alerts.newest_first if defined? alerts.newest_first
    (alerts.sort_by { |alert| [alert.created_at, alert.number] }).reverse
  end

  def get_alerts_for_orgs(business, organization_ids, state, slug_types, sort, direction, page_size, prev_cursor, next_cursor, resolutions, repository_visibilities, validities, is_publicly_leaked, is_multi_repo)
    empty_response = { alerts: [], total: 0, previous_cursor: nil, next_cursor: nil }

    selector = {
      business_selector: ::GitHub::Proto::SecretScanning::Api::V2::BusinessSelector.new(
        id: business.id,
        organization_ids: organization_ids,
        repository_visibilities: from_repo_visibilities_to_proto_enums(repository_visibilities),
        user_ids: [],
        user_filter: :NONE,
      ),
      feature_flags: get_tokens_api_feature_flags(business),
    }

    include_emu = (
      AdvancedSecurity::Features::Business::AdvancedSecurity.new(business).feature_available_for_user_repositories? &&
      SecurityProduct::Permissions::BusinessAuthz.new(business, actor: current_user).can_view_user_owned_repository_alerts?
    )

    if include_emu
      selector[:business_selector].user_filter = :ALL
    else
      return empty_response if organization_ids.empty?
    end

    failbot_hash = {
      business_id: business.id,
      organization_ids: organization_ids,
      include_emu:,
      previous_cursor: prev_cursor,
      next_cursor: next_cursor,
    }

    results = get_alerts(
      selector,
      state,
      slug_types,
      sort,
      direction,
      page_size,
      nil,
      failbot_hash,
      resolutions,
      prev_cursor,
      next_cursor,
      validities,
      is_publicly_leaked,
      is_multi_repo,
    )

    # Create lookup table by repository_id
    repos = results[:tokens].map(&:repository_id)
      .uniq
      .sort
      .each_slice(10)
      .map { |batch| Repository.where(id: batch) }
      .flatten
      .index_by(&:id)

    alerts = results[:tokens].filter_map do |token|
      repo = repos[token.repository_id]
      next unless repo

      GitHub::TokenScanning::Service::Client.wrap_token(token, repo)
    end

    alerts, _ = filter_tenant_rows(
      RequestScope.new(:business, business, "secret_scanning"),
      alerts,
      -> (alert) { alert.repository.id },
      repository_visibilities
    )

    {
      alerts: alerts,
      total: results[:total],
      previous_cursor: results[:previous_cursor],
      next_cursor: results[:next_cursor],
    }
  end

  def get_alerts_for_org(org, state, slug_types, sort, direction, page_size, current_page, previous_cursor, next_cursor, repo_ids, resolutions, repository_visibilities, validities, is_publicly_leaked, is_multi_repo)
    selector = {
      org_selector: ::GitHub::Proto::SecretScanning::Api::V2::OrgSelector.new(
        owner_id: org.id,
        repository_ids: repo_ids,
        repository_visibilities: from_repo_visibilities_to_proto_enums(repository_visibilities),
      ),
      feature_flags: get_tokens_api_feature_flags(org),
    }

    failbot_hash = {
      org_id: org.id,
      repository_ids: repo_ids,
      page_size: page_size,
      current_page: current_page,
      previous_cursor: previous_cursor,
      next_cursor: next_cursor,
    }

    results = get_alerts(
      selector,
      state,
      slug_types,
      sort,
      direction,
      page_size,
      current_page,
      failbot_hash,
      resolutions,
      previous_cursor,
      next_cursor,
      validities,
      is_publicly_leaked,
      is_multi_repo,
    )

    # Create lookup table by repository_id
    repos = results[:tokens].map(&:repository_id)
      .uniq
      .sort
      .each_slice(10)
      .map { |batch| Repository.where(id: batch) }
      .flatten
      .index_by(&:id)

    alerts = results[:tokens].filter_map do |token|
      repo = repos[token.repository_id]
      next unless repo

      GitHub::TokenScanning::Service::Client.wrap_token(token, repo)
    end

    alerts, _ = filter_tenant_rows(
      RequestScope.new(:organization, org, "secret_scanning"),
      alerts,
      -> (alert) { alert.repository.id },
      repository_visibilities
    )

    {
      alerts: alerts,
      total: results[:total],
      previous_cursor: results[:previous_cursor],
      next_cursor: results[:next_cursor],
      resolved_count: results[:resolved_count],
      unresolved_count: results[:unresolved_count]
    }
  end

  def get_alerts_for_repo(repo, state, slug_types, sort, direction, page_size, current_page, previous_cursor, next_cursor, resolutions, validities, is_publicly_leaked, is_multi_repo)
    selector = {
      repo_selector: ::GitHub::Proto::SecretScanning::Api::V2::RepoSelector.new(repository_id: repo.id),
      feature_flags: get_tokens_api_feature_flags(repo),
    }

    failbot_hash = {
      repo_id: repo.id,
      page_size: page_size,
      current_page: current_page,
      previous_cursor: previous_cursor,
      next_cursor: next_cursor,
    }

    results = get_alerts(selector, state, slug_types, sort, direction, page_size, current_page, failbot_hash, resolutions, previous_cursor, next_cursor, validities, is_publicly_leaked, is_multi_repo)
    alerts = GitHub::TokenScanning::Service::Client.wrap_tokens(results[:tokens], repo)
    alerts, _ = filter_tenant_rows(
      RequestScope.new(:repository, repo, "secret_scanning"),
      alerts,
      -> (alert) { alert.repository.id }
    )

    {
      alerts: alerts,
      total: results[:total],
      previous_cursor: results[:previous_cursor],
      next_cursor: results[:next_cursor],
      resolved_count: results[:resolved_count],
      unresolved_count: results[:unresolved_count]
    }
  end

  def get_alerts(selector_hash, state, slug_types, sort, direction, page_size, current_page, failbot_hash, resolutions, prev_cursor, next_cursor, validities, is_publicly_leaked, is_multi_repo)
    token_state = nil
    if state == :open
      token_state = :OPEN
    elsif state == :resolved
      token_state = :RESOLVED
    end
    failbot_hash = failbot_hash.merge(token_state: token_state)

    # invalid case passing both :before and :after paging cursors
    if prev_cursor && next_cursor
      deliver_error! 422, message: "cannot specify both 'before' and 'after' parameters"
    end

    # invalid case passing both a cursor (:before/:after) and :page
    # this would be mixing offset and cursor pagination
    if (prev_cursor || next_cursor) && current_page
      deliver_error! 422, message: "cannot specify both 'page' and 'before' or 'after' parameters"
    end

    # passing in an empty string for the cursor on the first request with sort/direction is allowed
    # passing in an opaque cursor on future requests should not be mixed with sort/direction parameters
    if (prev_cursor.present? || next_cursor.present?) && (sort || direction)
      deliver_error! 422, message: "cannot specify 'sort' or 'direction' with 'before' or 'after' parameters, cursors already have a sort order determined by the initial request that returned them"
    end

    begin
      prev_cursor = Base64.urlsafe_decode64(prev_cursor) unless prev_cursor.blank?
      next_cursor = Base64.urlsafe_decode64(next_cursor) unless next_cursor.blank?
    rescue ArgumentError
      deliver_error!(400, message: "Unable to decode paging cursor.")
    end

    if sort.present? && !(sort == "created" || sort == "updated")
      deliver_error!(400, message: "Invalid sort. Valid options are 'created' and 'updated'.")
    end

    if direction.present? && !(direction == "asc" || direction == "desc")
      deliver_error!(400, message: "Invalid direction. Valid options are 'asc' and 'desc'.")
    end

    sort_order = GitHub::Proto::SecretScanning::Api::V2::SortOrder::CREATED_DESCENDING
    if sort || direction
      sort_order = get_service_enum_from_sort_order(sort, direction)
    end

    # pagination[:page] already had this logic, but now we're checking the params[:page] parameter directly
    # to prevent the case where a consumer passes both :page and :before/:after paging cursors
    page = current_page.to_i > 1 ? current_page.to_i : 1

    if prev_cursor || next_cursor
      page = 0
    end

    get_tokens_params = {
      token_slugs: slug_types,
      token_state: token_state,
      sort_order: sort_order,
      limit: page_size,
      page: page,
      resolution: resolutions,
      validity: validities,
      previous_cursor: prev_cursor,
      next_cursor: next_cursor,
      publicly_leaked: is_publicly_leaked,
      multi_repo: is_multi_repo,
    }.merge(selector_hash)

    response = GitHub::TokenScanning::Service::Client.new(current_user).get_tokens(get_tokens_params)
    check_response_for_errors(response, :get_tokens, failbot_hash)

    results = response&.data&.tokens || []
    total = response&.data&.resolved_count + response&.data&.unresolved_count

    # Remove the `=` padding at the end of the strings, to make them shorter. (It can be parsed without that padding.)
    previous_cursor = unless response&.data&.previous_cursor.nil? || response&.data&.previous_cursor.empty?
      Base64.urlsafe_encode64(response&.data&.previous_cursor, padding: false)
    end
    next_cursor = unless response&.data&.next_cursor.nil? || response&.data&.next_cursor.empty?
      Base64.urlsafe_encode64(response&.data&.next_cursor, padding: false)
    end

    {
      tokens: results,
      total: total,
      previous_cursor: previous_cursor,
      next_cursor: next_cursor,
      resolved_count: response&.data&.resolved_count,
      unresolved_count: response&.data&.unresolved_count,
    }
  end

  def check_response_for_errors(response, method, report_payload)
    deliver_error!(503, message: "Secret scanning unavailable. Please try again later.") if response.nil?

    # special handling for invalid format cursor, since we can't validate it here in dotcom
    # not a great idea to echo internal error message, so handle field specifically
    if response.error.present?
      argument = response.error&.meta&.dig("argument")
      cursor_param_names = %w[req.previous_cursor req.next_cursor]
      if cursor_param_names.include?(argument)
        case response.error.code
        when :malformed # serialization failure
          deliver_error!(400, message: "Unable to decode paging cursor.")
        when :invalid_argument # cursor invalid for use case (i.e. trying to use `after` cursor as `before` param)
          deliver_error!(400, message: "Paging cursor is invalid.")
        end
      end
    end

    unless response.error.nil?
      Failbot.report(
        StandardError.new("Unable to retrieve secret scanning alerts"),
        {
          method: method.to_s,
          error_code: response.error.code,
          error_message: response.error.msg,
        }.merge(report_payload)
      )
      deliver_error!(500, message: "Error fetching secret scanning alerts.")
    end
  end

  def resolve_alert_from_service(alert_number, repository:, resolution:, actor:, dismissal_comment: nil)
    feature_flags = []
    resolution = resolution.to_s.upcase.to_sym
    GitHub::TokenScanning::Service::Client.new(current_user).resolve_token(
      repository_id: repository.id,
      token_id: alert_number,
      resolver_id: current_user.id,
      resolution: resolution,
      default_branch_name: repository.default_branch,
      feature_flags: feature_flags,
      resolution_comment: dismissal_comment,
    )
  end

  # Overrides handling of empty input schema
  def deliver_schema_validation_error!(result)
    error_messages = result.error_messages.join("\n")
    error_messages = "JSON object must be supplied as the request body." if error_messages == "For 'links/0/schema', nil is not an object."
    deliver_error! 422, message: "Invalid request.\n\n#{error_messages}"
  end

  sig do params(
    alert: T.any(GitHub::TokenScanning::Service::Token, TokenScanResult),
    repository: Repository,
    location_blobs: T.untyped,
    multiline_secret_with_newline: T::Boolean,
  ).void
  end
  def set_raw_secret(alert, repository, location_blobs, multiline_secret_with_newline: false)
    SecretScanning::Util::RawSecret.set_raw_secret(alert, repository, location_blobs, multiline_secret_with_newline: multiline_secret_with_newline)
    if alert.raw_secret.nil?
      deliver_error! 500, message: "Unable to fetch secret for alert number #{alert.number}."
    end
  end

  def set_raw_secrets(alerts, repository, location_blobs)
    alerts.each do |alert|
      set_raw_secret(alert, repository, location_blobs)
    end
  end

  def self.get_first_locations(alerts)
    alerts.collect(&:first_location).compact
  end

  private

  def alert_number
    int_id_param!(key: :alert_number)
  end

  def setup_cursor_paging_links(results)
    if results[:previous_cursor].present?
      @links.add_current({ before: nil, after: nil, page: nil }, rel: "first")
      @links.add_current({
        before: results[:previous_cursor],
        after: nil,
        page: nil,
        sort: nil,
        direction: nil
      }, rel: "prev")
    end

    if results[:next_cursor].present?
      @links.add_current({
        before: nil,
        after: results[:next_cursor],
        page: nil,
        sort: nil,
        direction: nil
      }, rel: "next")
    end
  end
end
