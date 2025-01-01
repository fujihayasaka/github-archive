# typed: true
# frozen_string_literal: true

class Api::Staff::App < Api::App

  # Access to staff APIs is limited to the staff_api scope.
  # To generate a token with this scope, use:
  # curl -u $username -d '{"scopes":["site_admin"],"note":"test"}'
  # -X POST https://api.github.com/authorizations
  # Individual actions and endpoints can be further restricted
  # using role based authentication, where request method and
  # the specific endpoint are used to determine access
  before do
    control_access :staff_api, request_method: env["REQUEST_METHOD"], route_pattern: Api::App.route_pattern(env), allow_integrations: false, allow_user_via_granular_actor: false, disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed
  end

  private

  def audit_log_results(phrase, per_page: nil, page: nil)

    options = {
      phrase:       phrase,
      current_user: current_user,
    }
    options[:per_page] = per_page if per_page.present?
    options[:page] = page if page.present?

    query = Audit::Driftwood::Query.new_stafftools_query(options)
    query.execute
  end

  # Override Api::App#repo_nwo_from_path
  #
  # Slightly similar to app/api/lfs.rb
  #
  # Because we run the :staff_api control access in a before block,
  # Sinatra has not yet populated `params` from the request so we
  # can't use `params[:owner]` and `params[:repo]` to determine
  # the repository name-with-owner.
  #
  # To avoid memoizing a false-negative result, we only invoke
  # the base class implementation (which memoizes) if params is present.
  #
  # This is a best effort implementation, that just works for the
  # existing endpoints under Api::Staff. The avid reader might notice
  # this is prone to error if the :staff_api access were to rely on the
  # this method returning the expected value when params are not present.
  def repo_nwo_from_path
    return super if params.present?
    find_repo_nwo_from_router || find_repo_nwo_from_path
  end
end
