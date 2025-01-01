# typed: true
# frozen_string_literal: true

class PullRequestDiffViewController < AbstractRepositoryController

  def update_preferences # rubocop:todo GitHub/UseRestfulActions
    @pull = find_pull_request
    redirect_to :back unless @pull

    if logged_in?
      if diff_preference.present?
        diff_view = diff_preference.to_sym
        current_user.set_diff_preference(diff_view)

        analytics_event \
          category: "PullRequestDiffViewPreferences",
          action: diff_view
      end

      if ignore_whitespace?
        @pull.set_ignore_whitespace_preference(current_user)

        analytics_event \
          category: "PullRequestDiffViewPreferences",
          action: "ignore_whitespace"
      else
        @pull.clear_ignore_whitespace_preference(current_user)

        analytics_event \
          category: "PullRequestDiffViewPreferences",
          action: "show_whitespace"
      end
    end

    redirect_to referrer_path
  end

  private

  def ignore_whitespace?
    params[:w] == "1"
  end

  def diff_preference
    params[:diff]
  end

  def referrer_path
    uri = begin
      URI(request.referrer)
    rescue ArgumentError, URI::InvalidURIError
      URI(pull_request_files_url(
        current_repository.owner_display_login,
        current_repository.name,
        @pull.number,
      ))
    end

    original_query_params = Rack::Utils.parse_nested_query(uri.query).deep_symbolize_keys
    new_query_params = { w: params[:w], diff: params[:diff] }.compact
    uri.query = original_query_params.merge(new_query_params).to_query
    uri.to_s
  end

  def find_pull_request
    PullRequest.with_number_and_repo(params[:id].to_i, current_repository)
  end
end
