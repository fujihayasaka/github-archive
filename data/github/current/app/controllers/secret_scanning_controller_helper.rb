# typed: strict
# frozen_string_literal: true

require "secret_scanning_proto"

module SecretScanningControllerHelper
  extend T::Helpers

  include SecretScanning::Features::FeatureFlagHelper
  include GitHub::TokenScanning::SecretScanningHelper
  include TreeHelper

  requires_ancestor { ApplicationController }
  requires_ancestor { ActionView::Rendering }

  BLANKSLATE_DUPLICATE_QUALIFIERS = :duplicate_qualifiers
  BLANKSLATE_NO_MATCHES = :no_matches
  BLANKSLATE_NO_OPEN_SECRETS = :no_secrets
  BLANKSLATE_NO_GENERIC_MATCHES = :no_generic_matches
  BLANKSLATE_INVALID_QUERY = :invalid_query

  module GroupByAggregation
    TOKEN_TYPE = "secret-type"
    TOKEN_PROVIDER = "provider"
    REPOSITORY = "repo"
    OWNER = "owner"
    OWNER_TYPE = "owner-type"

    TO_SERVICE_ENUM = T.let({
      TOKEN_TYPE => GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByAggregation::SECRET_TYPE,
      TOKEN_PROVIDER => GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByAggregation::SECRET_PROVIDER,
      REPOSITORY => GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByAggregation::REPOSITORY,
      # organization/user/owner are special cases, since it's not a valid enum value
      # we fetch the repo aggregation and transform it here in the monolith
      OWNER => GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByAggregation::REPOSITORY,
      OWNER_TYPE => GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByAggregation::REPOSITORY,
    }, T::Hash[String, Integer])
  end

  PAGE_SIZE = 25
  QUERY_PARSER = Search::Queries::SecurityCenter::SecretScanningQuery

  # Check if cursor pagination is enabled for the given scope (org, business, repo) or the current user.
  # Supports enabling via either the scope entity hierarchy or per-user flag.
  sig { params(scope: T.any(Organization, Business, Repository, User)).returns(T::Boolean) }
  def acv_cursor_pagination_enabled?(scope)
    feature_flag_enabled_in_hierarchy?(scope, SecretScanning::Features::FeatureFlagHelper::FeatureFlags::ACV_CURSOR_PAGINATION) ||
      current_user.feature_flag_enabled?(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::ACV_CURSOR_PAGINATION, default: false)
  end

  # Shared cursor pagination logic for org, business, and repo secret scanning controllers.
  sig { params(service: SecretScanning::AlertQueryService, scope: T.any(Organization, Business, Repository, User)).returns(T::Array[T.untyped]) }
  def fetch_alerts_with_cursor_pagination(service, scope:)
    after_cursor = params[:after].try(:to_str)
    before_cursor = params[:before].try(:to_str)

    # Decode cursors if present (they're Base64 URL-safe encoded)
    begin
      after_cursor = Base64.urlsafe_decode64(after_cursor) unless after_cursor.blank?
      before_cursor = Base64.urlsafe_decode64(before_cursor) unless before_cursor.blank?
    rescue ArgumentError, TypeError
      # Invalid Base64 or non-string cursor - treat as no cursor provided
      after_cursor = nil
      before_cursor = nil
    end

    cursor_provided = after_cursor.present? || before_cursor.present?
    cursor_pagination_enabled = acv_cursor_pagination_enabled?(scope)

    if cursor_provided
      alerts, open_alert_count, closed_alert_count, response, request_error = service.get_alerts_with_response(
        after_cursor: after_cursor,
        before_cursor: before_cursor,
        per_page: PAGE_SIZE
      )

      # If the error is specifically a cursor deserialization/validation failure
      # (user-edited URL), fall back to the first page. The service layer already
      # suppresses Failbot for these, so this avoids the "loading failed" blankslate
      # without generating noise.
      # For non-cursor errors (real TSS outages), let the error propagate normally
      # so the controller shows the error blankslate and tracks a graceful failure.
      if request_error.present? && SecretScanning::Services::ServiceHelper.cursor_error?(response)
        return service.get_alerts_with_response(page: 0, per_page: PAGE_SIZE)
      end

      [alerts, open_alert_count, closed_alert_count, response, request_error]
    elsif cursor_pagination_enabled
      # Keyset cursor - page: 0 tells TSS to use fast indexed queries instead of OFFSET
      service.get_alerts_with_response(page: 0, per_page: PAGE_SIZE)
    else
      # Skip cursor - existing behavior with page numbers
      service.get_alerts_with_response(page: current_page, per_page: PAGE_SIZE)
    end
  end

  # Retrieves :cursor from params and returns it as base64 decoded.
  # NOTE: 2026/02/19
  # In the future, we could choose not to worry about success and just return only nil for decoding failure.
  # But for at least this current deploy for metrics pages, responding with an error response in the failure case
  # because of old cursors forces users to refresh the page to prevent the confusing situation of suddenly receiving page 1 when paginating.
  sig { returns([T.nilable(String), T::Boolean]) }
  def cursor_from_params
    cursor = params[:cursor].try(:to_str)
    return nil, true unless cursor
    begin
      [Base64.urlsafe_decode64(cursor), true]
    rescue ArgumentError, TypeError
      # 2026/02/19 - Logging to keep track of users with old cursor access page. Can remove after enough time passes and logs stop emitting.
      GitHub.logger.info("Failed to decode cursor; likely detected old cursor",
        "gh.catalog_service": "github/secret-scanning",
      )
      [nil, false]
    end
  end

  # Extract next_cursor from a service response, Base64 encoded for URL use.
  sig { params(response: T.untyped).returns(T.nilable(String)) }
  def extract_next_cursor(response)
    cursor = response&.data&.try(:next_cursor)
    return nil if cursor.blank?
    Base64.urlsafe_encode64(cursor, padding: false)
  end

  # Extract prev_cursor from a service response, Base64 encoded for URL use.
  sig { params(response: T.untyped).returns(T.nilable(String)) }
  def extract_prev_cursor(response)
    cursor = response&.data&.try(:previous_cursor)
    return nil if cursor.blank?
    Base64.urlsafe_encode64(cursor, padding: false)
  end

  # Redirect to strip ?page= param when cursor pagination is enabled.
  # Returns true if a redirect was performed, false otherwise.
  sig { params(scope: T.any(Organization, Business, Repository, User)).returns(T::Boolean) }
  def redirect_if_page_param_with_cursor_pagination!(scope:)
    if params[:page].present? && acv_cursor_pagination_enabled?(scope)
      redirect_to url_for(only_path: true, params: request.query_parameters.except("page"))
      return true
    end
    false
  end

  sig { params(scope: T.any(Organization, Business), query: String).returns(T::Hash[Symbol, T.untyped]) }
  def get_secret_scanning_filter_option_paths(scope, query)
    filter_option_paths = {}

    path_method =
      case
      when scope.is_a?(Organization)
        method(:security_center_alerts_secret_scanning_menu_content_path)
      when scope.is_a?(Business)
        method(:security_center_alerts_secret_scanning_menu_content_enterprise_path)
      else
        T.absurd(scope)
      end

    if scope.is_a?(Business)
      id = "select-menu-#{SecureRandom.uuid}"
      filter_option_paths[:owner] = {
        id: id,
        path: path_method.call(
          dropdown_enum: GroupByAggregation::OWNER,
          is_multiselect: true,
          menu_id: id,
          qualifier: QUERY_PARSER::QUALIFIER_OWNER,
          query: query,
        )
      }
    end

    unless scope.is_a?(Repository)
      id = "select-menu-#{SecureRandom.uuid}"
      filter_option_paths[:repository] = {
        id: id,
        path: path_method.call(
          dropdown_enum: GroupByAggregation::REPOSITORY,
          is_multiselect: true,
          menu_id: id,
          qualifier: QUERY_PARSER::QUALIFIER_REPOSITORY,
          query: query,
        )
      }
    end

    id = "select-menu-#{SecureRandom.uuid}"
    filter_option_paths[:secret_type] = {
      id: id,
      path: path_method.call(
        dropdown_enum: GroupByAggregation::TOKEN_TYPE,
        is_multiselect: true,
        menu_id: id,
        qualifier: QUERY_PARSER::QUALIFIER_SECRET_TYPE,
        query: query,
      )
    }

    id = "select-menu-#{SecureRandom.uuid}"
    filter_option_paths[:provider] = {
      id: id,
      path: path_method.call(
        dropdown_enum: GroupByAggregation::TOKEN_PROVIDER,
        is_multiselect: true,
        menu_id: id,
        qualifier: QUERY_PARSER::QUALIFIER_PROVIDER,
        query: query,
      )
    }

    filter_option_paths
  end

  sig { returns(T.untyped) }
  def rendered_loading_secrets_failed_component
    Primer::Beta::BorderBox.new.render_in(view_context) do |c|
      c.with_body do
        SecretScanning::AlertCentricView::Blankslates::LoadingSecretsFailedComponent
          .new
          .render_in(view_context)
      end
    end
  end

  sig { returns(T.untyped) }
  def rendered_no_active_repositories_component
    Primer::Beta::BorderBox.new.render_in(view_context) do |c|
      c.with_body do
        SecretScanning::AlertCentricView::Blankslates::NoActiveRepositoriesComponent
          .new
          .render_in(view_context)
      end
    end
  end

  sig { returns(T.untyped) }
  def rendered_no_repos_to_show_component
    Primer::Beta::BorderBox.new.render_in(view_context) do |c|
      c.with_body do
        SecretScanning::AlertCentricView::Blankslates::NoReposToShowComponent
          .new
          .render_in(view_context)
      end
    end
  end

  ##
  # Render a SelectMenuContentComponent for the given set of options
  #
  # +filter_options+::  An array of filter groups, each with an array of options and optional title.
  #                     ex: [{ items: [{ count: 1, label: "xx", description: "yy", slug: "xx/yy" }], title: "" }, {...}]
  # +menu_id+::         The HTML id of the menu to render.
  # +qualifier+::       The search qualifier for the current filter.
  # +is_multiselect+::  Boolean string indicating whether the menu should be a multiselect.
  sig { params(filter_options: T.untyped, menu_id: String, qualifier: String, is_multiselect: String).returns(T.untyped) }
  def render_filter_content_component(filter_options, menu_id, qualifier, is_multiselect)
    filter_options.each_with_index do |tab, i|
      # Add id to each tab to connect the tab with the existing filter input.
      tab[:id] = "#{menu_id}-list-#{i + 1}"
      # Each item needs to specify its associated query qualifier.
      tab[:items].each { |item| item[:qualifier] = qualifier }
    end

    select_menu_tabs = filter_options.map do |tab|
      SecurityCenter::SelectMenu::Tab.new(
        id: tab[:id],
        items: tab[:items].map do |item|
          SecurityCenter::SelectMenu::Item.new(**item.slice(:count, :description, :label, :qualifier, :slug))
        end,
        title: tab[:title]
      )
    end

    render(
      SecurityCenter::SelectMenuContentComponent.new(
        is_multiselect: ActiveModel::Type::Boolean.new.cast(params[:is_multiselect]),
        query: params[:query],
        query_parser: QUERY_PARSER,
        tabs: select_menu_tabs
      ),
      layout: false
    )
  end
end
