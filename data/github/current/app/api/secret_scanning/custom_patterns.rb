# typed: strict
# frozen_string_literal: true

class Api::SecretScanning::CustomPatterns < Api::App
  # List org custom patterns
  get "/organizations/:organization_id/secret-scanning/custom-patterns", operation_id: "secret-scanning/list-org-custom-patterns" do
    org = find_org!
    deliver_error!(404) unless custom_patterns_rest_api_enabled?(org)
    access_org!(org)
    control_access(
      :read_org_security_product_configurations,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
    )
    service = SecretScanning::Services::CustomPatternsService.new(current_user)
    options = { selector: { org_selector: { owner_id: org.id } } }
    options[:filter] = build_filter_options
    res = service.get_custom_patterns(options)
    deliver_error!(500, message: "An error occurred. Please try again later.") if res.nil? || res.error.present?
    patterns = res.data.custom_patterns.to_a
    deliver_raw(SecretScanning::Util::CustomPatternSerializer.serialize_api_list(patterns))
  end

  # Bulk create org custom patterns
  post "/organizations/:organization_id/secret-scanning/custom-patterns", operation_id: "secret-scanning/bulk-create-org-custom-patterns", read_from_replicas: false do
    org = find_org!
    deliver_error!(404) unless custom_patterns_rest_api_enabled?(org)
    access_org!(org)
    control_access(
      :manage_org_security_product_configurations,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
    )
    service = SecretScanning::Services::CustomPatternsService.new(current_user)
    data = receive_with_openapi
    patterns_input = data["patterns"]

    deliver_error!(422, message: "patterns must not be empty") if patterns_input.blank?

    patterns = patterns_input.map do |p|
      {
        expression: p["pattern"],
        display_name: p["name"],
        post_processing: build_post_processing(p),
      }
    end

    created_patterns, validation_errors, err = service.batch_create_custom_patterns(
      patterns: patterns,
      owner_id: org.id,
      owner_scope: :ORGANIZATION_SCOPE,
      owner: org,
    )
    if err
      deliver_error!(500, message: "An error occurred. Please try again later.")
    elsif validation_errors
      deliver_raw({ message: "Validation Failed", validation_errors: validation_errors }, status: 422)
    elsif created_patterns
      deliver_raw({ created_patterns: SecretScanning::Util::CustomPatternSerializer.serialize_api_list(created_patterns) }, status: 201)
    else
      deliver_error!(500, message: "An error occurred. Please try again later.")
    end
  end

  # List enterprise custom patterns
  get "/enterprises/:enterprise_id/secret-scanning/custom-patterns", operation_id: "secret-scanning/list-enterprise-custom-patterns" do
    enterprise = find_enterprise!
    deliver_error!(404) unless custom_patterns_rest_api_enabled?(enterprise)
    access_biz!(enterprise)
    control_access(
      :manage_enterprise_security_product_configurations,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
    )
    service = SecretScanning::Services::CustomPatternsService.new(current_user)
    options = { selector: { business_selector: { business_id: enterprise.id } } }
    options[:filter] = build_filter_options
    res = service.get_custom_patterns(options)
    deliver_error!(500, message: "An error occurred. Please try again later.") if res.nil? || res.error.present?
    patterns = res.data.custom_patterns.to_a
    deliver_raw(SecretScanning::Util::CustomPatternSerializer.serialize_api_list(patterns))
  end

  # Bulk delete org custom patterns
  delete "/organizations/:organization_id/secret-scanning/custom-patterns", operation_id: "secret-scanning/bulk-delete-org-custom-patterns", read_from_replicas: false do
    org = find_org!
    deliver_error!(404) unless custom_patterns_rest_api_enabled?(org)
    access_org!(org)
    control_access(
      :manage_org_security_product_configurations,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
    )
    service = SecretScanning::Services::CustomPatternsService.new(current_user)
    data = receive_with_openapi
    patterns_input = data["patterns"]

    deliver_error!(422, message: "patterns must not be empty") if patterns_input.blank?

    to_delete = patterns_input.map do |p|
      {
        id: p["pattern_id"],
        row_version: p["custom_pattern_version"],
      }
    end

    error, res_code = validate_custom_pattern_delete_input(service, to_delete)
    if error
      if service.is_row_version_mismatch?(error, res_code)
        deliver_error!(412, message: "Precondition Failed: The custom_pattern_version does not match the current version of the pattern. Retrieve the latest version and try again.")
      elsif res_code == :invalid_argument
        deliver_error!(422, message: error)
      else
        deliver_error!(500, message: "An error occurred. Please try again later.")
      end
    end

    response = service.delete_custom_patterns(
      patterns_with_row_versions: to_delete,
      owner_id: org.id,
      owner_scope: GitHub::Proto::SecretScanning::Api::V3::OwnerScope::ORGANIZATION_SCOPE,
      deleted_by_user_id: current_user.id,
      post_delete_action: parse_post_delete_action(data["post_delete_action"]),
    )
    error, res_code = service.check_for_custom_patterns_twirp_error(response)
    if error
      if service.is_row_version_mismatch?(error, res_code)
        deliver_error!(412, message: "Precondition Failed: The custom_pattern_version does not match the current version of the pattern. Retrieve the latest version and try again.")
      else
        deliver_error!(500, message: "An error occurred. Please try again later.")
      end
    else
      deliver_empty(status: 204)
    end
  end

  # Update org custom pattern
  patch "/organizations/:organization_id/secret-scanning/custom-patterns/:pattern_id", operation_id: "secret-scanning/update-org-custom-pattern", read_from_replicas: false do
    org = find_org!
    deliver_error!(404) unless custom_patterns_rest_api_enabled?(org)
    access_org!(org)
    control_access(
      :manage_org_security_product_configurations,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
    )
    service = SecretScanning::Services::CustomPatternsService.new(current_user)
    data = receive_with_openapi
    pattern_id = params[:pattern_id].to_i

    deliver_error!(422, message: "pattern_id must be a positive integer") if pattern_id < 1

    custom_pattern_version = data["custom_pattern_version"]

    # Default to empty string when pattern is absent in partial updates.
    # Proto3 treats "" as the default value, so TSS will skip updating the expression field.
    expression = data["pattern"] || ""

    response = service.update_custom_pattern(
      id: pattern_id,
      expression: expression,
      post_processing: build_post_processing(data),
      change_type: :DRY_RUN,
      owner: org,
      owner_id: org.id,
      owner_scope: GitHub::Proto::SecretScanning::Api::V3::OwnerScope::ORGANIZATION_SCOPE,
      row_version: custom_pattern_version,
    )
    error, res_code = service.check_for_custom_patterns_twirp_error(response)
    if error
      if service.is_row_version_mismatch?(error, res_code)
        deliver_error!(412, message: "Precondition Failed: The custom_pattern_version does not match the current version of the pattern. Retrieve the latest version and try again.")
      elsif res_code == :not_found
        deliver_error!(404, message: "Custom pattern not found")
      else
        deliver_error!(500, message: "An error occurred. Please try again later.")
      end
    end

    response_data = response&.data
    if response_data&.error.present?
      deliver_error!(500, message: "An error occurred. Please try again later.")
    end

    updated_pattern = response_data&.custom_pattern
    if updated_pattern
      deliver_raw(SecretScanning::Util::CustomPatternSerializer.serialize_api(updated_pattern))
    else
      deliver_error!(500, message: "An error occurred. Please try again later.")
    end
  end

  # Bulk create enterprise custom patterns
  post "/enterprises/:enterprise_id/secret-scanning/custom-patterns", operation_id: "secret-scanning/bulk-create-enterprise-custom-patterns", read_from_replicas: false do
    enterprise = find_enterprise!
    deliver_error!(404) unless custom_patterns_rest_api_enabled?(enterprise)
    access_biz!(enterprise)
    control_access(
      :manage_enterprise_security_product_configurations,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
    )
    service = SecretScanning::Services::CustomPatternsService.new(current_user)
    data = receive_with_openapi
    patterns_input = data["patterns"]

    deliver_error!(422, message: "patterns must not be empty") if patterns_input.blank?

    patterns = patterns_input.map do |p|
      {
        expression: p["pattern"],
        display_name: p["name"],
        post_processing: build_post_processing(p),
      }
    end

    created_patterns, validation_errors, err = service.batch_create_custom_patterns(
      patterns: patterns,
      owner_id: enterprise.id,
      owner_scope: :BUSINESS_SCOPE,
      owner: enterprise,
    )
    if err
      deliver_error!(500, message: "An error occurred. Please try again later.")
    elsif validation_errors
      deliver_raw({ message: "Validation Failed", validation_errors: validation_errors }, status: 422)
    elsif created_patterns
      deliver_raw({ created_patterns: SecretScanning::Util::CustomPatternSerializer.serialize_api_list(created_patterns) }, status: 201)
    else
      deliver_error!(500, message: "An error occurred. Please try again later.")
    end
  end

  # Bulk delete enterprise custom patterns
  delete "/enterprises/:enterprise_id/secret-scanning/custom-patterns", operation_id: "secret-scanning/bulk-delete-enterprise-custom-patterns", read_from_replicas: false do
    enterprise = find_enterprise!
    deliver_error!(404) unless custom_patterns_rest_api_enabled?(enterprise)
    access_biz!(enterprise)
    control_access(
      :manage_enterprise_security_product_configurations,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
    )
    service = SecretScanning::Services::CustomPatternsService.new(current_user)
    data = receive_with_openapi
    patterns_input = data["patterns"]

    deliver_error!(422, message: "patterns must not be empty") if patterns_input.blank?

    to_delete = patterns_input.map do |p|
      {
        id: p["pattern_id"],
        row_version: p["custom_pattern_version"],
      }
    end

    error, res_code = validate_custom_pattern_delete_input(service, to_delete)
    if error
      if service.is_row_version_mismatch?(error, res_code)
        deliver_error!(412, message: "Precondition Failed: The custom_pattern_version does not match the current version of the pattern. Retrieve the latest version and try again.")
      elsif res_code == :invalid_argument
        deliver_error!(422, message: error)
      else
        deliver_error!(500, message: "An error occurred. Please try again later.")
      end
    end

    response = service.delete_custom_patterns(
      patterns_with_row_versions: to_delete,
      owner_id: enterprise.id,
      owner_scope: GitHub::Proto::SecretScanning::Api::V3::OwnerScope::BUSINESS_SCOPE,
      deleted_by_user_id: current_user.id.to_i,
      post_delete_action: parse_post_delete_action(data["post_delete_action"]),
    )
    error, res_code = service.check_for_custom_patterns_twirp_error(response)
    if error
      if service.is_row_version_mismatch?(error, res_code)
        deliver_error!(412, message: "Precondition Failed: The custom_pattern_version does not match the current version of the pattern. Retrieve the latest version and try again.")
      else
        deliver_error!(500, message: "An error occurred. Please try again later.")
      end
    else
      deliver_empty(status: 204)
    end
  end

  # Update enterprise custom pattern
  patch "/enterprises/:enterprise_id/secret-scanning/custom-patterns/:pattern_id", operation_id: "secret-scanning/update-enterprise-custom-pattern", read_from_replicas: false do
    enterprise = find_enterprise!
    deliver_error!(404) unless custom_patterns_rest_api_enabled?(enterprise)
    access_biz!(enterprise)
    control_access(
      :manage_enterprise_security_product_configurations,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
    )
    service = SecretScanning::Services::CustomPatternsService.new(current_user)
    data = receive_with_openapi
    pattern_id = params[:pattern_id].to_i

    deliver_error!(422, message: "pattern_id must be a positive integer") if pattern_id < 1

    custom_pattern_version = data["custom_pattern_version"]

    # Default to empty string when pattern is absent in partial updates.
    # Proto3 treats "" as the default value, so TSS will skip updating the expression field.
    expression = data["pattern"] || ""

    response = service.update_custom_pattern(
      id: pattern_id,
      expression: expression,
      post_processing: build_post_processing(data),
      change_type: :DRY_RUN,
      owner: enterprise,
      owner_id: enterprise.id,
      owner_scope: GitHub::Proto::SecretScanning::Api::V3::OwnerScope::BUSINESS_SCOPE,
      row_version: custom_pattern_version,
    )
    error, res_code = service.check_for_custom_patterns_twirp_error(response)
    if error
      if service.is_row_version_mismatch?(error, res_code)
        deliver_error!(412, message: "Precondition Failed: The custom_pattern_version does not match the current version of the pattern. Retrieve the latest version and try again.")
      elsif res_code == :not_found
        deliver_error!(404, message: "Custom pattern not found")
      else
        deliver_error!(500, message: "An error occurred. Please try again later.")
      end
    end

    response_data = response&.data
    if response_data&.error.present?
      deliver_error!(500, message: "An error occurred. Please try again later.")
    end

    updated_pattern = response_data&.custom_pattern
    if updated_pattern
      deliver_raw(SecretScanning::Util::CustomPatternSerializer.serialize_api(updated_pattern))
    else
      deliver_error!(500, message: "An error occurred. Please try again later.")
    end
  end

  # List repo custom patterns
  get "/repositories/:repository_id/secret-scanning/custom-patterns", operation_id: "secret-scanning/list-repo-custom-patterns" do
    repo = find_repo!
    deliver_error!(404) unless custom_patterns_rest_api_enabled?(repo)
    access_repo!(repo)
    control_access(
      :read_secret_scanning_alerts,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
    )
    service = SecretScanning::Services::CustomPatternsService.new(current_user)
    options = { selector: { repo_selector: { repository_id: repo.id } } }
    options[:filter] = build_filter_options
    res = service.get_custom_patterns(options)
    deliver_error!(500, message: "An error occurred. Please try again later.") if res.nil? || res.error.present?
    patterns = res.data.custom_patterns.to_a
    deliver_raw(SecretScanning::Util::CustomPatternSerializer.serialize_api_list(patterns))
  end

  # Bulk create repo custom patterns
  post "/repositories/:repository_id/secret-scanning/custom-patterns", operation_id: "secret-scanning/bulk-create-repo-custom-patterns", read_from_replicas: false do
    repo = find_repo!
    deliver_error!(404) unless custom_patterns_rest_api_enabled?(repo)
    access_repo!(repo)
    control_access(
      :write_secret_scanning_alerts,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
    )
    service = SecretScanning::Services::CustomPatternsService.new(current_user)
    data = receive_with_openapi
    patterns_input = data["patterns"]

    deliver_error!(422, message: "patterns must not be empty") if patterns_input.blank?

    patterns = patterns_input.map do |p|
      {
        expression: p["pattern"],
        display_name: p["name"],
        post_processing: build_post_processing(p),
      }
    end

    created_patterns, validation_errors, err = service.batch_create_custom_patterns(
      patterns: patterns,
      owner_id: repo.id,
      owner_scope: :REPOSITORY_SCOPE,
      owner: repo,
    )
    if err
      deliver_error!(500, message: "An error occurred. Please try again later.")
    elsif validation_errors
      deliver_raw({ message: "Validation Failed", validation_errors: validation_errors }, status: 422)
    elsif created_patterns
      deliver_raw({ created_patterns: SecretScanning::Util::CustomPatternSerializer.serialize_api_list(created_patterns) }, status: 201)
    else
      deliver_error!(500, message: "An error occurred. Please try again later.")
    end
  end

  # Bulk delete repo custom patterns
  delete "/repositories/:repository_id/secret-scanning/custom-patterns", operation_id: "secret-scanning/bulk-delete-repo-custom-patterns", read_from_replicas: false do
    repo = find_repo!
    deliver_error!(404) unless custom_patterns_rest_api_enabled?(repo)
    access_repo!(repo)
    control_access(
      :write_secret_scanning_alerts,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
    )
    service = SecretScanning::Services::CustomPatternsService.new(current_user)
    data = receive_with_openapi
    patterns_input = data["patterns"]

    deliver_error!(422, message: "patterns must not be empty") if patterns_input.blank?

    to_delete = patterns_input.map do |p|
      {
        id: p["pattern_id"],
        row_version: p["custom_pattern_version"],
      }
    end

    error, res_code = validate_custom_pattern_delete_input(service, to_delete)
    if error
      if service.is_row_version_mismatch?(error, res_code)
        deliver_error!(412, message: "Precondition Failed: The custom_pattern_version does not match the current version of the pattern. Retrieve the latest version and try again.")
      elsif res_code == :invalid_argument
        deliver_error!(422, message: error)
      else
        deliver_error!(500, message: "An error occurred. Please try again later.")
      end
    end

    response = service.delete_custom_patterns(
      patterns_with_row_versions: to_delete,
      owner_id: repo.id,
      owner_scope: GitHub::Proto::SecretScanning::Api::V3::OwnerScope::REPOSITORY_SCOPE,
      deleted_by_user_id: current_user.id.to_i,
      post_delete_action: parse_post_delete_action(data["post_delete_action"]),
    )
    error, res_code = service.check_for_custom_patterns_twirp_error(response)
    if error
      if service.is_row_version_mismatch?(error, res_code)
        deliver_error!(412, message: "Precondition Failed: The custom_pattern_version does not match the current version of the pattern. Retrieve the latest version and try again.")
      else
        deliver_error!(500, message: "An error occurred. Please try again later.")
      end
    else
      deliver_empty(status: 204)
    end
  end

  # Update repo custom pattern
  patch "/repositories/:repository_id/secret-scanning/custom-patterns/:pattern_id", operation_id: "secret-scanning/update-repo-custom-pattern", read_from_replicas: false do
    repo = find_repo!
    deliver_error!(404) unless custom_patterns_rest_api_enabled?(repo)
    access_repo!(repo)
    control_access(
      :write_secret_scanning_alerts,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
    )
    service = SecretScanning::Services::CustomPatternsService.new(current_user)
    data = receive_with_openapi
    pattern_id = params[:pattern_id].to_i

    deliver_error!(422, message: "pattern_id must be a positive integer") if pattern_id < 1

    custom_pattern_version = data["custom_pattern_version"]

    # Default to empty string when pattern is absent in partial updates.
    # Proto3 treats "" as the default value, so TSS will skip updating the expression field.
    expression = data["pattern"] || ""

    response = service.update_custom_pattern(
      id: pattern_id,
      expression: expression,
      post_processing: build_post_processing(data),
      change_type: :DRY_RUN,
      owner: repo,
      owner_id: repo.id,
      owner_scope: GitHub::Proto::SecretScanning::Api::V3::OwnerScope::REPOSITORY_SCOPE,
      row_version: custom_pattern_version,
    )
    error, res_code = service.check_for_custom_patterns_twirp_error(response)
    if error
      if service.is_row_version_mismatch?(error, res_code)
        deliver_error!(412, message: "Precondition Failed: The custom_pattern_version does not match the current version of the pattern. Retrieve the latest version and try again.")
      elsif res_code == :not_found
        deliver_error!(404, message: "Custom pattern not found")
      else
        deliver_error!(500, message: "An error occurred. Please try again later.")
      end
    end

    response_data = response&.data
    if response_data&.error.present?
      deliver_error!(500, message: "An error occurred. Please try again later.")
    end

    updated_pattern = response_data&.custom_pattern
    if updated_pattern
      deliver_raw(SecretScanning::Util::CustomPatternSerializer.serialize_api(updated_pattern))
    else
      deliver_error!(500, message: "An error occurred. Please try again later.")
    end
  end

  private

  sig { params(org: Organization).void }
  def access_org!(org)
    deliver_error!(404, message: "Feature not available in this organization.") unless SecretScanning::Features::Org::CustomPatterns.new(org).feature_available?
  end

  sig { params(biz: Business).void }
  def access_biz!(biz)
    deliver_error!(404, message: "Feature not available in this enterprise.") unless biz.seats_plan_full?
    deliver_error!(404, message: "Feature not available in this enterprise.") unless SecretScanning::Features::Business::CustomPatterns.new(biz).feature_available?
  end

  sig { params(repo: Repository).void }
  def access_repo!(repo)
    deliver_error!(404, message: "Feature not available in this repository.") unless SecretScanning::Features::Repo::CustomPatterns.new(repo).feature_available?
  end

  sig { params(actor: T.any(Organization, Business, Repository)).returns(T::Boolean) }
  def custom_patterns_rest_api_enabled?(actor)
    SecretScanning::Features::FeatureFlagHelper.feature_flag_enabled_in_hierarchy?(actor, SecretScanning::Features::FeatureFlagHelper::FeatureFlags::CUSTOM_PATTERNS_REST_API)
  end

  # Validates the input for a bulk delete request. Checks for invalid pattern_ids,
  # duplicates, missing/blank custom_pattern_version, existence, and version mismatches.
  # Returns [error_message, code] or [nil, nil] if valid.
  sig { params(service: SecretScanning::Services::CustomPatternsService, to_delete: T::Array[T::Hash[Symbol, T.untyped]]).returns([T.nilable(String), T.nilable(Symbol)]) }
  def validate_custom_pattern_delete_input(service, to_delete)
    pattern_ids = to_delete.map { |p| p[:id] }

    # TODO: Change invalid pattern_id error to return 400 (bad request) instead of 422,
    # to match path parameter validation conventions (see alert_number in repository_secret_scanning.rb).
    non_positive_id = pattern_ids.find { |id| !id.is_a?(Integer) || id < 1 }
    return "pattern_id '#{non_positive_id}' does not exist", :invalid_argument if non_positive_id

    if pattern_ids.uniq.length != pattern_ids.length
      return "Duplicate pattern_id values are not allowed", :invalid_argument
    end

    service.validate_custom_pattern_versions(to_delete)
  end

  sig { params(value: T.nilable(String)).returns(Symbol) }
  def parse_post_delete_action(value)
    case value
    when "resolve_alerts"
      :RESOLVE_ALERTS
    else
      :DELETE_ALERTS
    end
  end

  sig { params(pattern_input: T::Hash[String, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
  def build_post_processing(pattern_input)
    {
      start_delimiter: pattern_input["start_delimiter"] || "",
      end_delimiter: pattern_input["end_delimiter"] || "",
      must_match: pattern_input["must_match"] || [],
      must_not_match: pattern_input["must_not_match"] || [],
    }
  end

  # Builds the filter options hash for get_custom_patterns based on query params:
  #   - `state`: "published" or "unpublished" (absent = both)
  #   - `push_protection`: "enabled" or "disabled" (absent = no filter)
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def build_filter_options
    included_states = parse_state_param!
    push_protected_filter = parse_push_protection_param!

    {
      included_states: included_states,
      push_protected_filter: push_protected_filter,
    }
  end

  VALID_STATE_VALUES = T.let(%w[published unpublished].freeze, T::Array[String])
  VALID_PUSH_PROTECTION_VALUES = T.let(%w[enabled disabled].freeze, T::Array[String])

  sig { returns(T::Array[Symbol]) }
  def parse_state_param!
    return [:PUBLISHED, :UNPUBLISHED] unless params[:state]

    state = params[:state].downcase
    unless VALID_STATE_VALUES.include?(state)
      deliver_error!(422, message: "state is invalid: it must be one of 'published' or 'unpublished'")
    end

    state == "published" ? [:PUBLISHED] : [:UNPUBLISHED]
  end

  sig { returns(Symbol) }
  def parse_push_protection_param!
    return :INCLUDE_ALL unless params[:push_protection]

    value = params[:push_protection].downcase
    unless VALID_PUSH_PROTECTION_VALUES.include?(value)
      deliver_error!(422, message: "push_protection is invalid: it must be 'enabled' or 'disabled'")
    end

    value == "enabled" ? :PUSH_PROTECTED : :NOT_PUSH_PROTECTED
  end
end
