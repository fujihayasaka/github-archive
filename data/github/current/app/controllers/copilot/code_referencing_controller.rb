# typed: true
# frozen_string_literal: true

require "monolith-twirp-snippy-snippy"

class Copilot::CodeReferencingController < ApplicationController
  include LanguageHelper

  before_action :login_required
  before_action :dotcom_required
  before_action :copilot_access_required
  before_action :feature_required
  before_action :testing_feature_required, except: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Ballast,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    only: [:new, :show]

  ALLOWED_EDITORS = %w[vscode intellij vs].freeze

  def show
    # Snippy requires a trailing comma in the cursor, so we'll add one if it's missing
    cursor = params[:cursor]
    cursor += "," unless cursor.end_with?(",")

    files, stats, snippet = Rails.cache.fetch("copilot-match-#{cursor}",
      expires_in: 1.hour,
      stats_key: "copilot.code_referencing.cache") do
      result = twirp_client.files_for_match(cursor: cursor)
      return render_404 if result.data.nil?
      [
        result.data.file_matches.map(&:to_h),
        result.data.license_stats.to_h,
        result.data.snippet
      ]
    end

    total_matches = files.count

    # Filter out licenses that are excluded by params before we paginate the result
    if params[:exclude_licenses]
      excluded_licenses = params[:exclude_licenses].split(",")
      files = files.reject { |file| excluded_licenses.include?(file[:license]) }
    end

    paginated_files = files.paginate(page: params[:page], per_page: PAGE_SIZE)

    licenses = stats.fetch(:count, []).map do |key, count|
      { key: key, label: license_name(key), count: count.to_i }
    end

    # Add the highlighted lines and repo metadata for each file
    enriched_files = async_enriched_files(paginated_files, snippet).sync


    GlobalInstrumenter.instrument(::Copilot::Events::CODE_REFERENCING_PAGE_VIEW, {
      copilot_user: copilot_authorizer.copilot_user,
      editor_version: editor_version,
      fingerprint: cursor
    })

    GitHub.dogstats.increment(
      "copilot.code_referencing.show",
      tags: ["page:#{params[:page].to_i + 1}", "editor:#{editor_version}"]
    )

    context_region_title "GitHub Copilot references"

    render_react_app(
      payload: {
        # total number of results for this search
        total_results: paginated_files.total_entries,
        # the number of pages for this results search
        total_pages: paginated_files.total_pages,
        # total number of matches for this cursor
        total_matches: total_matches,
        files: enriched_files,
        licenses: licenses
      },
      title: "Copilot code references",
    )
  end

  # This is a temporary endpoint to allow us to create code referencing URLs without going through
  # the entire IDE flow. It will be removed or moved to stafftools before launch
  def new
    render "copilot/code_referencing/new"
  end

  # This is a temporary endpoint to allow us to create code referencing URLs without going through
  # the entire IDE flow. It will be removed or moved to stafftools before launch
  def create
    match = twirp_client.match(source: params[:code])
    if match.data.snippets.empty?
      render json: { error: "No references found" }, status: :not_found
      return
    end

    cursor = match.data.snippets.first.cursor

    redirect_to "/github-copilot/code_referencing?cursor=#{cursor}"
  end

  private

  NO_LICENSE = "NOASSERTION".freeze
  PAGE_SIZE = 10

  def editor_version
    from_params = (params[:editor] || "").downcase
    editor = ALLOWED_EDITORS.find { |e| e == from_params }
    editor || "unknown"
  end

  # Enrich each file entry with the highlighted lines for its snippet and other metadata from
  # the repo
  def async_enriched_files(files, snippet)
    # Snippy matches ignore whitespace, so let's strip whitespace from the snippet so we can use it to
    # match against file contents with differing whitespace and newlines
    snippet_with_normalized_whitespace = snippet.split(/\s/)
      .reject(&:empty?)
      .map { |word| Regexp.escape(word) }
      .join('\s*')
    snippet_regex = Regexp.new(snippet_with_normalized_whitespace)

    contents_promises = files.map do |file|
      file[:license] = license_name(file[:license])
      file[:ref] = { value: file[:commit_id], label: file[:commit_id].slice(0, 7) }
      file[:language] = file[:file_type]
      file[:language_color] = language_color(Linguist::Language[file[:language]])

      repo = Repository.with_name_with_owner(file[:nwo])
      unless repo
        instrument_snippet_rendering_error(file, "missing_repo")
        next
      end

      entry = repo.tree_entry(file[:commit_id], file[:path])

      # Use the snippet regex to find where the snippet occurs in each file. We normalize
      # the file beforehand by stripping out whitespace, to handle cases where the file has
      # more whitespace than the snippet
      match = entry.data.gsub(/[ \t]+/, "").match(snippet_regex)

      unless match
        instrument_snippet_rendering_error(file, "missing_snippet")
        next file
      end

      start_line = match.pre_match.count("\n")
      match_lines_count = match[0].count("\n") + 1

      # Allow the file url to be permalinked to its matched lines
      file[:url] = file[:url] + "#L#{start_line + 1}-L#{start_line + match_lines_count}"

      entry.async_file_lines.then do |lines|
        file[:colorized_lines] = highlight_with_context(lines, start_line, match_lines_count)
        file
      end
    rescue GitRPC::Error => e
      # We're either in dev or the commit has been deleted
      instrument_snippet_rendering_error(file, "missing_commit")

      # Log the specific error for easier investigation later
      GitHub.logger.warn("Rescued GitRPC error", {
        "cursor": params[:cursor],
        "exception.message": e.message,
      })

      nil
    end.compact

    Promise.all(contents_promises)
  end

  # Given the index of the first line of a match, the number of lines in the match, wrap each line
  # of the match in <mark> highlighting tags and add context lines before and after the match
  def highlight_with_context(lines, start_line, match_lines_count, context_length: 2)
    colorized_lines = lines.slice(start_line, match_lines_count).map do |line|
      line[:html].gsub!(/(^\s*)/, '\1<mark>') # preserve whitespace before highlighted section
      line[:html] = "#{line[:html]}</mark>"
      line
    end

    # Add prefix and suffix lines if present
    prefix = if start_line == 0
      []
    else
      beginning = [start_line - context_length, 0].max
      lines[beginning..start_line - 1]
    end

    end_of_snippet = start_line + match_lines_count
    suffix = lines[end_of_snippet..(end_of_snippet + context_length)]

    prefix + colorized_lines + suffix
  end

  def twirp_client
    MonolithTwirp::Snippy::Snippy::V1::SnippyAPIClient.new(faraday_client)
  end

  def faraday_client
    GitHub::FaradayClient::Internal.new(url: GitHub.copilot_snippy_url, request: { timeout: 3 }) do |conn|
      conn.request(:retry, max: 2)
      conn.use GitHub::FaradayMiddleware::RequestID
      conn.authorization(:Bearer, snippy_token)
      conn.adapter Faraday.default_adapter
    end
  end

  memoize def snippy_token
    if Rails.env.development?
      # Paste your short-lived, locally-generated, farm-to-table proxy token here
      return ""
    end

    headers = {
      editor_version: "2",
      editor_plugin_version: "2",
      request_id: "1",
      ip_address: "127.0.0.1"
    }
    envelope = Copilot::Envelope.new(copilot_authorizer, headers)
    envelope.envelope[:token]
  end

  memoize def copilot_authorizer
    current_copilot_user&.copilot_authorizer_object_no_snippy
  end

  def instrument_snippet_rendering_error(file, error)
    GitHub.dogstats.increment(
      "copilot.code_referencing.snippet.#{error}",
      tags: dogstats_tags(file)
    )
    GitHub.logger.warn("Error rendering snippet", {
      "cursor": params[:cursor],
      "exception.message": error
    })
  end

  def dogstats_tags(file)
    ["language:#{file[:language]}"]
  end

  def copilot_access_required
    unless copilot_authorizer.access_allowed?
      render_404
    end
  end

  def feature_required
    unless FeatureFlag.vexi.enabled_or_raise?(:code_referencing_dotcom, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      render_404
    end
  end

  def testing_feature_required
    unless FeatureFlag.vexi.enabled_or_raise?(:code_referencing_dotcom_testing, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      render_404
    end
  end

  def target_for_conditional_access
    # This is safe due to :login_required
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def resource_for_conditional_access
    return self unless logged_in?

    current_user
  end

  def license_name(key, fallback: nil)
    return "unknown" if key == NO_LICENSE
    Licensee::License.find_by_key(key.downcase)&.name || fallback || key
  end
end
