# typed: false
# frozen_string_literal: true

require "csv"

module BlobHelper
  # Used to provide raw_domain_token for build_raw_url helper
  include RawBlob::AbstractRepositoryHelper
  include FeatureFlagHelper

  class SizeLimitExceeded < RuntimeError; end

  EMPTY_BLOB_TIPS = [
    "“We shape clay into a pot, but it is the emptiness inside that holds whatever we want.”",
    "“It was not the feeling of completeness I so needed, but the feeling of not being empty.”—Jonathan Safran Foer",
    "“There is just something obvious about emptiness, even when you try to convince yourself otherwise.”—Sarah Dessen",
    "“Human affairs are like a chess-game: only those who do not take it seriously can be called good players. Life is like an earthen pot: only when it is shattered, does it manifest its emptiness.”—Seneca (Roman philosopher, mid-1st century AD)",
    "“The example of the raft shows dharmas should be treated as provisional, as means to an end. The same holds good of emptiness too, the negation of dharmas.”—Gautama Siddharta",
    "“I felt very still and empty, the way the eye of a tornado must feel, moving dully along in the middle of the surrounding hullabaloo.”—Sylvia Plath",
    "“There was emptiness more profound than the void between the stars, for which there was no here and there and before and after, and yet out of that void the entire plenum of existence sprang forth.”—Heinz R. Pagels",
    "“You can only fit so many words in a postcard, only so many in a phone call, only so many into space before you forget that words are sometimes used for things other than filling emptiness.”—Sarah Kay",
    "“The artist’s job is not to succumb to despair but to find an antidote for the emptiness of existence.”—Woody Allen",
    "“Beyond the edge of the world there is a space where emptiness and substance neatly overlap, where past and future form a continuous, endless loop. And, hovering about, there are signs no one has ever read, chords no one has ever heard.”—Haruki Murakami",
    "“It iss better to look at the sky than live there. Such an empty place; so vague. Just a country where the thunder goes and things disappear.”—Truman Capote",
    "“We become aware of the void as we fill it.”—Antonio Porchia",
    "“Emptiness which is conceptually liable to be mistaken for sheer nothingness is in fact the reservoir of infinite possibilities.”—D.T. Suzuki",
    "“In all our searching, the only thing we have found that makes the emptiness bearable is each other.”—Carl Sagan",
    "Become totally empty\nQuiet the restlessness of the mind\nOnly then will you witness everything unfolding from emptiness\n—Lao Tzu",
    "“Nothing has an unlikely quality. It is heavy.”—Jeanette Winterson",
  ]

  def empty_blob_tip
    EMPTY_BLOB_TIPS.sample
  end

  def blob_fullwidth?
    if defined?(@blob_fullwidth)
      @blob_fullwidth
    else
      @blob_fullwidth = params[:fullscreen] == "true" ||
        show_marketplace_sidebar? ||
        issue_form_template_file? ||
        custom_slash_command? ||
        discussion_template_file?
    end
  end

  def show_marketplace_sidebar?
    (workflow_yaml_file? || dev_container_file?) && !onboarding_guidance?
  end

  def onboarding_guidance?
    params[:guidance_task].present?
  end

  def dependabot_yaml_file?
    return false unless FeatureFlag.vexi.enabled_or_raise?(:dependabot_editor_improvements, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    return true if params[:dependabot_template].present?
    return false unless params[:path].present?
    return false unless params[:path].size == 2
    return false unless params[:path].first == ".github"
    return false unless params[:path].second == "dependabot.yml" || params[:path].second == "dependabot.yaml"
    true
  end

  def workflow_yaml_file?
    return false unless GitHub.actions_enabled?
    return true if params[:workflow_template].present?
    return true if params[:pages_workflow_template].present?
    return false unless params[:path].present?
    return false unless params[:path].size == 3
    return false unless params[:path].first == ".github"
    return false unless %w[workflows workflows-lab].include?(params[:path].second)
    return false unless params[:path].last.end_with?(".yml", ".yaml")
    true
  end

  def dev_container_file?
    return true if params[:dev_container_template].present?
    return false if params[:path].blank?
    return false unless params[:path].is_a?(Array)

    # Check for [".devcontainer.json"] -or- [".devcontainer", **, "devcontainer.json"]
    params[:path].join("/").match?(Codespaces::DevContainer::VALID_DEVCONTAINER_PATH_GLOB)
  end

  def stack_template_file?
    return false unless GitHub.stacks_enabled?
    return false unless params[:path].present?
    return false unless params[:path].size == 3
    return false unless params[:path].first == ".github"
    return false unless params[:path].second == "stacks"
    return false unless params[:path].last == "stack.yml" || params[:path].last == "stack.yaml"
    true
  end

  def issue_form_template_file?
    return @issue_form_template_file if defined?(@issue_form_template_file)

    @issue_form_template_file = if params[:path]
      IssueTemplates.valid_yaml_template_path?(
        full_template_path,
        current_repository,
      )
    else
      false
    end
  end

  def discussion_template_file?
    return @discussion_template_file if defined?(@discussion_template_file)

    @discussion_template_file = if params[:path]
      DiscussionTemplates.valid_path?(
        full_template_path
      )
    else
      false
    end
  end

  def custom_slash_command?
    return @custom_slash_command if defined?(@custom_slash_command)

    @custom_slash_command = if params[:path]
      ConfigAsCode::RepoFileTemplate.slash_commands_configuration_path?(
        current_repository,
        full_template_path,
        current_user
      )
    else
      params[:command_template] && current_user&.slash_commands_enabled?
    end
  end

  def sidebar_doc
    if issue_form_template_file?
      IssueForms::SidebarDocs
    elsif discussion_template_file?
      DiscussionForms::SidebarDocs
    end
  end

  def custom_slash_commands_docs_url
    "#{GitHub.help_url}/early-access/github/save-time-with-slash-commands/syntax-for-user-defined-slash-commands"
  end

  def full_template_path
    Array(params[:path]).join("/")
  end

  def conditional_tag(name, condition, options = nil, &block)
    if condition
      content_tag name, capture(&block), options
    else
      capture(&block)
    end
  end

  def human_mode(mode)
    case mode
    when "100644"
      "file"
    when "100755"
      "executable file"
    when "120000"
      "symbolic link"
    else
      "non-standard mode"
    end
  end

  def render_image_or_raw?(blob)
    return true if force_render_raw? && blob.git_lfs?
    !blob.viewable?
  end

  def blob_short_path(blob)
    blob.oid[0, 7]
  end

  def blob_url_as_raw
    url_for(raw: true)
  end

  # Identifies if this file is a CSV or TSV file
  def csv_or_tsv?(extname)
    TABLE_EXTNAMES.include?(extname.downcase)
  end

  TABLE_EXTNAMES = Set.new %w(.csv .tsv)

  # Generates a cache key for the CSV/TSV rendering
  # based on the OID and whether or not the current
  # blob is a snippet or not.
  #
  # Returns the key as a String.
  def blob_csv_cache_key(blob)
    parts = %W(blob csv #{blob.oid})
    parts << "snippet" if blob.snippet?

    parts.join(":")
  end

  # Parses a CSV or TSV file using Ruby's native CSV library
  #
  # Returns an Array with the following elements:
  #   rows  - An Array of CSV rows, or nil in the case of an error.
  #   error - An error String, or nil in the case of success.
  def parse_csv_or_tsv(blob)
    GitHub.dogstats.increment("blob", tags: ["action:parse_csv_or_tsv"])
    GitHub.cache.fetch(blob_csv_cache_key(blob)) do
      GitHub.dogstats.increment("cache.miss", tags: ["action:blob.parse_csv_or_tsv"])
      parse_csv_or_tsv!(blob)
    end
  end

  def parse_csv_or_tsv!(blob)
    start = GitHub::Dogstats.monotonic_time
    begin
      # Jamming too many lines into the DOM kills GitHub.  Only ~3% of all CSVs
      # on GitHub are >600 KB. Of THAT set, >75% are larger than 1 MB, which GitHub doesn't show anyway.
      # That said, the FS will stop sending content after 512k, see https://github.com/github/github/issues/38045#issuecomment-72699838
      raise SizeLimitExceeded if blob.size > 512.kilobytes
      csv_file = blob.extname.downcase == ".csv"

      separator = csv_file ? "," : "\t"

      # there can't be spaces at the end of a row
      sanitized_data = blob.data.gsub(/#{separator} +$/, "#{separator}\x00")

      # there must not be any spaces between a separator and a quote
      sanitized_data = sanitized_data.gsub(/#{separator} +\"/, "#{separator}\"")

      # strip any starting empty newlines--we can't use #strip, due to potentially empty tsv cells
      sanitized_data = sanitized_data.gsub(/^[\r\n]+/, "").gsub(/[\r\n]+$/, "")

      # strip any leading Byte Order Mark characters from unicode csv/tsvs
      transcoded_blob = GitHub::Encoding.guess_and_transcode(sanitized_data)

      if transcoded_blob && transcoded_blob.encoding == ::Encoding::UTF_8
        sanitized_data = transcoded_blob.gsub(/\A\uFEFF/, "")
      end

      # No separators? Don't even bother parsing
      if csv_file
        unless sanitized_data =~ /\,/
          raise CSV::MalformedCSVError.new "No commas found in this CSV file", 0
        end
      else # tsv file
        unless sanitized_data =~ /\t/
          raise CSV::MalformedCSVError.new "No tabs found in this TSV file", 0
        end
      end

      csv_rows = CSV.parse(sanitized_data, col_sep: separator)
      header = csv_rows.first

      csv_rows.each_with_index do |row, index|
        if row.length != header.length
          raise CSV::MalformedCSVError.new("It looks like row #{index + 1} should actually have #{header.length} #{'column'.pluralize(header.length)}, instead of #{row.length}", index)
        end
      end

      GitHub.dogstats.timing_since("blob.process.csv.success", start)
      [csv_rows, nil]
    rescue CSV::MalformedCSVError => e
      GitHub.dogstats.timing_since("blob.process.csv.error", start)
      [nil, "We can make this file <a href='#{GitHub.help_url}/articles/rendering-csv-and-tsv-data'>beautiful and searchable</a> if this error is corrected: #{e}".html_safe] # rubocop:disable Rails/OutputSafety
    rescue SizeLimitExceeded => e
      GitHub.dogstats.timing_since("blob.process.csv.error", start)
      [nil, "We can't make this file <a href='#{GitHub.help_url}/articles/rendering-csv-and-tsv-data'>beautiful and searchable</a> because it's too large.".html_safe] # rubocop:disable Rails/OutputSafety
    end
  end

  ## Extracted from BlobController/AbstractRepository/RawBlob to enable
  ## renderable_blob_url to work for both repos and gists.

  # Build the raw url for GistsController#raw and BlobController#raw
  #
  # type          - The type of raw url we're building.  Valid values are:
  #                 :gist and :repository
  # route_options - A hash of options for the route helper.
  #
  # Returns a URL as a string.
  def build_raw_url(type: :repository, route_options: {})
    route_options ||= {}

    if GitHub.subdomain_isolation
      route_options[:host] = GitHub.urls.raw_host_name
    end

    if type == :gist
      if GitHub.private_mode_enabled?
        scope = "Gist:#{route_options[:user_id]}/#{route_options[:gist_id]}/#{route_options[:sha]}/#{route_options[:file]}"
        token = current_user.signed_auth_token(scope: scope,
                                               expires: RawBlob::EXPIRES[:blob].from_now)
        route_options[:token] = token
      end

      raw_gist_blob_codeload_url(route_options)
    else
      # raw_domain_token included via RawBlob::AbstractRepositoryHelper
      if token = raw_domain_token(:blob)
        route_options[:token] = token
      end

      raw_blob_codeload_url(route_options)
    end
  end

  # Generates a URL to a raw gist blob served by codeload.
  #
  # options - An options hash.
  #           :host  - The hostname for the URL.
  #           :token - A token to be included in the query string.
  #
  # Returns a String URL.
  def raw_gist_blob_codeload_url(options)
    scheme = request.ssl? ? "https" : "http"
    host = options.fetch(:host, request.host)

    path = [
      GitHub.subdomain_isolation? ? nil : %w(raw),
      "gist",
      escape_url_path(options[:user_id]),
      escape_url_path(options[:gist_id]),
      "raw",
      escape_url_path(options[:sha]),
      escape_url_path(options[:file]),
    ].compact.join("/")

    query = options.slice(:token).to_query
    query_string = query.empty? ? "" : "?#{query}"

    "#{scheme}://#{host}/#{path}#{query_string}"
  end

  # Generates a URL to a raw blob served by codeload.
  #
  # options - An options hash.
  #           :host  - The hostname for the URL.
  #           :token - A token to be included in the query string.
  #
  # Returns a String URL.
  def raw_blob_codeload_url(options)
    scheme = request.ssl? ? "https" : "http"
    host = options.fetch(:host, request.host)

    path = [
      GitHub.subdomain_isolation? ? nil : %w(raw),
      escape_url_path(params[:user_id]),
      escape_url_path(params[:repository]),
      escape_url_branch(params[:name]),
      escape_url_paths(params[:path]),
    ].compact.join("/")

    query = options.slice(:token, :sanitize).to_query
    query_string = query.empty? ? "" : "?#{query}"

    "#{scheme}://#{host}/#{path}#{query_string}"
  end

  # The media domain url
  #
  # repository - The repository this media blob is being served for
  def media_domain_url(repository, oid)
    path = Array(params[:path]).join("/")
    TreeEntryRenderHelper.lfs_blob_url(current_user, repository, tree_name, path, oid)
  end

  # Gets the final raw URL for a file, free from any extra redirects.  Raw URLs
  # from external domains will have an expiring token.
  #
  # blob                  - The blob we're rendering
  # repo_or_gist          - The repository or gist this blob belongs to
  # pre_generated_raw_url - Fall back to this url for gists
  #
  # Returns a URL as a string
  def renderable_blob_url(blob, repo_or_gist, pre_generated_raw_url = nil)
    return pre_generated_raw_url if repo_or_gist.is_a?(Gist)

    if blob.git_lfs?
      media_domain_url(repo_or_gist, blob.git_lfs_oid)
    else
      blob_url_as_raw
    end
  end

  # Public: Detect the codemirror for a filename
  #
  # Returns the codemirror mode name if we can detect it
  # Else Returns ""
  def detect_filename_language(filename)
    languages = languages_for_filename(filename)
    languages.any? ? languages.last.codemirror_mime_type : ""
  end

  def detect_filename_language_with_details(filename)
    languages = languages_for_filename(filename)

    languages.last if languages.any?
  end

  def languages_for_filename(filename)
    # Strip any null byte characters before detecting language.
    filename = filename.to_s.delete("\0")

    languages = Linguist::Language.find_by_filename(filename)
    languages.any? ? languages : Linguist::Language.find_by_extension(filename)
  end
end
