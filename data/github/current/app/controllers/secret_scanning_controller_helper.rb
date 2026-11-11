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
