# typed: true
# frozen_string_literal: true

module Api::App::PersonalAccessTokensHelper
  extend T::Helpers
  include GranularPermissionsHelper

  requires_ancestor { Api::App }

  SUPPORTED_SORT_KEYS = %w[created_at].freeze
  SUPPORTED_SORT_DIRECTIONS = %w[asc desc].freeze

  def ensure_api_enabled_for_org!(org)
    deliver_error! 404 unless org.patsv2_enabled?
  end

  def sort_pats(rel)
    if params[:sort].present?
      sort_key = params[:sort]
      deliver_error! 400 unless SUPPORTED_SORT_KEYS.include?(sort_key)

      direction = params[:direction] || "desc"
      deliver_error! 400 unless SUPPORTED_SORT_DIRECTIONS.include?(direction)

      rel.order(sort_key => direction)
    else
      rel.order(created_at: :desc)
    end
  end

  def fetch_filters(org)
    {}.tap do |filters|
      filters[:owner] = find_owners if params["owner"]
      filters[:repository] = org.repositories.find_by(name: params["repository"]) if params["repository"]
      filters[:permission] = parse_permission_string(params["permission"]) if params["permission"]
      filters[:last_used_before] = time_param!("last_used_before") if params["last_used_before"]
      filters[:last_used_after] = time_param!("last_used_after") if params["last_used_after"]
      filters[:token_ids] = params["token_id"] if params["token_id"]
    end
  end

  def find_owners
    return nil unless params[:owner].present?

    owner_logins = params[:owner]
    return nil if owner_logins.empty?

    User.with_logins(owner_logins)
  end
end
