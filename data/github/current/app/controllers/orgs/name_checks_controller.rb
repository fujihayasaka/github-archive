# typed: true
# frozen_string_literal: true

class Orgs::NameChecksController < ApplicationController
  include OrganizationsHelper
  include OrganizationsControllerMethods
  include Orgs::Invitations::RateLimiting
  include GitHub::RateLimitedRequest
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  # Allow requests from React apps using the verifiedFetch function
  allow_verified_fetch only: [:create]

  before_action :try_parse_json_params, only: :create
  before_action :login_required
  after_action :customer_category_instrumentation

  rate_limit_requests \
    if: :orgs_rate_limit_filter,
    only: :create,
    key: :rate_limit_key,
    max: 100,
    ttl: 1.hour,
    at_limit: :at_rate_limit

  def create
    return head 400 if profile_name.blank?

    respond_to do |format|
      format.html_fragment do
        render \
          partial: "organizations/signup/name_message",
          formats: :html,
          status: hash_for_response[:status],
          locals: {
            exists: hash_for_response[:payload][:exists],
            unavailable: hash_for_response[:payload][:unavailable],
            reserved_login_keyword: hash_for_response[:payload][:reserved_login_keyword],
            name: hash_for_response[:payload][:name],
            is_name_modified: hash_for_response[:payload][:is_name_modified],
            not_alphanumeric: hash_for_response[:payload][:not_alphanumeric],
            over_max_length: hash_for_response[:payload][:over_max_length],
          }
      end

      format.json do
        render json: hash_for_response[:payload], status: hash_for_response[:status]
      end
    end
  end

  private

  def profile_name
    params[:value]
  end

  memoize def hash_for_response
    name = profile_name.parameterize(preserve_case: true)

    status = 200
    payload = {
      exists: T.let(false, T::Boolean),
      unavailable: T.let(false, T::Boolean),
      name: name,
      is_name_modified: name != params[:value],
      not_alphanumeric: T.let(false, T::Boolean),
      over_max_length: T.let(false, T::Boolean),
    }

    # Check if the org name is valid. Checks include:
    # - Denylist (config/initializers/denylist.rb)
    # - Other logins reserved by staff via https://admin.github.com/stafftools/reserved_logins
    # - Recently deleted accounts
    # - Reserved login keywords
    login_reserved = ReservedLogin.reserved_with_reason?(
      name,
      persistent_client_id: persistent_client_id,
      skip_keyword_check: current_user.employee?,
    )

    if login_reserved[:reserved]
      status = 422

      if login_reserved[:reason] == :reserved_login_keyword
        payload[:reserved_login_keyword] = true
      else
        payload[:unavailable] = true
      end
    elsif User.find_by_login(name).present?
      status = 422
      payload[:exists] = true
    elsif !name.match?(User::LOGIN_REGEX)
      status = 422
      payload[:not_alphanumeric] = true
    elsif name.length > User::LOGIN_MAX_LENGTH
      status = 422
      payload[:over_max_length] = true
    end

    {
      status: status,
      payload: payload
    }
  end

  def rate_limit_key
    "organizations.check_name:#{current_user.id}"
  end
end
