# typed: true
# frozen_string_literal: true

# A controller that handles rendering patches and diffs. Due to security concerns
# around user supplied content in patches and diffs its best to serve them off of
# a different subdomain.
#
# Related Issue: https://github.com/github/github/issues/36923
#
# Production: https://patch-diff.githubusercontent.com
# Garage: https://patch-diff-garage.githubusercontent.com
#
# Enterprise is not taking advantage of this domain isolation currently.
#
# This is currently in use for pull request diffs and patches, but should also be
# used for compare view diffs and patches in the future.
class PatchDiffController < ApplicationController
  include RepositoryControllerMethods

  # Needed to test in prs-garage.githubusercontent.com
  skip_before_action :privacy_check, only: [:raw_patch, :raw_diff]
  skip_before_action :employee_only_unicorn, only: [:raw_patch, :raw_diff]
  # cap_bypass: These actions are served from a different domain in dotcom to prevent CSRF and other attacks, using
  # a SignedAuthToken to validate access. See https://github.com/github/github/pull/310275#issuecomment-1922749061
  # for more details.
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :disable_session
  before_action :ensure_proper_pr_subdomain
  before_action :set_x_repository_download_header, only: [:raw_diff, :raw_patch]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Spokes,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    only: [:raw_patch, :raw_diff]

  depends_on_clusters ApplicationRecord::Mysql5,
    only: [:raw_diff]

  rate_limit_requests only: [:raw_diff, :raw_patch],
    if: :limit_patch_diff?,
    max: :patch_diff_rate_limit_max,
    ttl: GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL,
    key: :default_rate_limit_key

  def raw_diff # rubocop:todo GitHub/UseRestfulActions
    render_raw_pull_request("diff")
  end

  def raw_patch # rubocop:todo GitHub/UseRestfulActions
    render_raw_pull_request("patch")
  end

  private

  def render_raw_pull_request(type)
    timeout_client_error do
      if @pull = find_pull_request
        if raw_auth_token_valid?
          unless @pull.historical_comparison.valid?
            return render status: 404, plain: "Sorry, this diff is unavailable."
          end

          full_index = !!params[:full_index]

          if type == "patch"
            content = @pull.historical_comparison.to_patch(full_index: full_index)
          else
            content = @pull.historical_comparison.to_diff(full_index: full_index)
          end

          # Security fix. See #36923
          render_error_for_pdf_headers(content) if GitHub.enterprise?
          render plain: content unless performed?
        else
          redirect_to redirect_back_to_pr_url
        end
      else
        redirect_to redirect_back_to_pr_url
      end
    end
  end

  def redirect_back_to_pr_url
    "#{GitHub.url}#{request.path.gsub(/^\/raw/, '')}"
  end

  def ensure_proper_pr_subdomain
    if GitHub.prs_content_domain?
      render_404 unless GitHub.prs_content_host_name == request.env["SERVER_NAME"]
    end
  end

  def raw_auth_token_valid?
    return true if current_repository.public?
    parsed_token = User.verify_signed_auth_token token: params[:token],
                                                 scope: pull_request_authorization_token_scope_key
    parsed_token.valid?
  end

  def find_pull_request
    current_repository &&
      PullRequest.with_number_and_repo(params[:id].to_i, current_repository,
        include: [{ issue: { comments: :user } }])
  end

  memoize def anon_patch_diff_rate_limit_max_percentage
    FeatureFlag.vexi.percentage_of_actors_value_or_raise(:anon_patch_diff_rate_limit_max) # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
  end

  def limit_patch_diff?
    logged_in? || (anon_patch_diff_rate_limit_max_percentage&.is_a?(Numeric) && anon_patch_diff_rate_limit_max_percentage > 0)
  end

  def patch_diff_rate_limit_max
    return 600 if logged_in?

    if anon_patch_diff_rate_limit_max_percentage&.is_a?(Numeric) && anon_patch_diff_rate_limit_max_percentage > 0
      anon_patch_diff_rate_limit_max_percentage * 100
    else
      5000
    end
  end

  def set_x_repository_download_header
    x_repository_download_header(current_repository) if current_repository
  end
end
