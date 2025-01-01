# typed: true
# frozen_string_literal: true

module Api::Serializer::SearchDependency
  include Kernel
  include Api::Serializer
  include Api::Serializer::IssuesDependency

  # Public
  def label_search_result_hash(results, options = {})
    item_serializer = lambda do |result|
      search_label_hash(result, options)
    end

    search_result_hash(results, item_serializer, options)
  end

  # Public
  def user_search_result_hash(results, options = {})
    item_serializer = lambda do |result|
      resource = result["_model"]
      serialize(:search_user_hash, resource, options)
    end

    search_result_hash(results, item_serializer, options)
  end

  # Public
  def topic_search_result_hash(results, options = {})
    item_serializer = lambda do |result|
      serialize(:search_topic_hash, result, options)
    end

    search_result_hash(results, item_serializer, options)
  end

  # Public
  def repo_search_result_hash(results, options = {})
    return nil unless results

    repos = results.results.map { |result| result["_model"] }
    # It's necessary to prefill internal repo associations here because the
    # `disabled?` check during serialization loads it in order to look for
    # an OFAC flag on the business.
    Repository.prefill_associations(repos, internal: options.current_user&.businesses&.any?)

    # The serialization of the repo object below causes a query for the
    # default_branch of each repo which in turn causes a serial GitRPC
    # call to each repo. We use IOPromise here to preload all
    # of the required GitRPC calls first, then rely on the per-request
    # memcached local caching to instantly answer the questions during
    # the serialization below.
    ref_promises = repos.map { |repo| repo.async_get_default_branch }
    Promise.all(ref_promises).sync

    item_serializer = lambda do |result|
      resource = result["_model"]
      serialize(:repository_hash, resource, options)
    end

    search_result_hash(results, item_serializer, options)
  end

  # Public
  def issue_search_result_hash(results, options = {})
    return nil unless results

    issues = results.results.map { |result| result["_model"] }
    IssuePrefiller.prefill(issues)
    Reaction::Summary.prefill(issues)
    options.search = true

    item_serializer = lambda do |result|
      resource = result["_model"]
      serialize(:issue_hash, resource, options)
    end

    search_result_hash(results, item_serializer, options)
  end

  # Public
  def code_search_result_hash(results, options = {})
    item_serializer = lambda do |result|
      serialize(:code_search_result_item_hash, result, options)
    end

    search_result_hash(results, item_serializer, options)
  end

  def blackbird_code_search_result_hash(results, options = {})
    item_serializer = lambda do |result|
      serialize(:blackbird_code_search_result_item_hash, result, options)
    end

    blackbird_search_result_hash(results, item_serializer, options)
  end

  def commit_search_result_hash(results, options = {})
    item_serializer = lambda do |result|
      serialize(:commit_search_result_item_hash, result, options)
    end

    search_result_hash(results, item_serializer, options)
  end

  def blackbird_search_result_hash(results, item_serializer, options = {})
    return nil unless results

    item_hashes = results[:results].map do |result|
      hash = item_serializer.call(result)
      if hash.nil?
        nil
      else
        hash[:score] = 1.0
        hash[:text_matches] = blackbird_text_matches(result, hash[:url]) if options[:highlight]
        hash
      end
    end

    {
      total_count: results[:result_count],
      incomplete_results: results[:results_incomplete] || false,
      items: item_hashes.compact,
    }
  end

  def blackbird_text_matches(result, object_url)
    # result looks like
    # {
    #   "snippets": [
    #     {
    #       "start": 0,
    #       "end": 7,
    #       "lines": ["foo", "bar"]
    #     }
    #   ],
    #   "term_matches": [
    #     {
    #       "start": 0,
    #       "end": 3
    #     },
    #     {
    #       "start": 4,
    #       "end": 7
    #     }
    #   ]
    # }

    result[:snippets].map do |snippet|
      snippet_start = snippet[:start]
      snippet_end = snippet[:end]
      joined = snippet[:lines].join("\n")
      matches = result[:term_matches].filter { |match| match[:start] >= snippet_start && match[:end] <= snippet_end }
      matches = matches.map do |match|
        match_start = match[:start] - snippet_start
        match_end = match[:end] - snippet_start
        {
          indices: [match_start, match_end],
          text: joined.slice(match_start, match_end - match_start),
        }
      end

      {
        object_url: object_url,
        object_type: "FileContent",
        property: "content",
        fragment: snippet[:lines].join("\n"),
        matches: matches
      }
    end
  end

  # Internal
  def search_result_hash(results, item_serializer, options = {})
    return nil unless results

    item_hashes = results.results.map do |result|
      hash = item_serializer.call(result)
      # Don't publish the actual score here, because that can be used
      # to detect terms in _private_ documents in the index
      # https://github.com/github/github/issues/133923#issue-557092962
      hash[:score] = 1.0
      hash[:text_matches] = text_matches(result) if options[:highlight]
      hash
    end

    {
      total_count: results.total,
      incomplete_results: results.timed_out,
      items: item_hashes,
    }
  end

  # Internal
  def blackbird_code_search_result_item_hash(result, options)
    repo = result[:repo]
    return nil unless repo
    repo_id = repo.id

    options = Api::SerializerOptions.from(options)

    file_path = result[:path]
    blob_sha = result[:blob_sha]
    commit_sha = result[:commit_sha]

    file_name = File.basename(file_path)

    hash = {
      name: file_name,
      path: file_path,
      sha: blob_sha,
      url: encoded_content_url("/repositories/#{repo_id}/contents/", file_path, { ref: commit_sha }),
      git_url: url("/repositories/#{repo_id}/git/blobs/#{blob_sha}"),
      html_url: encoded_html_url(repo.permalink, "/blob/#{commit_sha}/#{file_path}"),
      repository: simple_repository_hash(repo, options),
    }

    if options.accepts_semantic_version?("extended-search-results")
      file_size = result[:file_size]
      language = result[:language_name]
      # last_modified_at = file_info["timestamp"] # blackbird doesn't know this so we're going to omit it
      highlights_line_numbers = [] # this always seems to return an empty array in geyser anyway
      hash.update \
        file_size: file_size,
        line_numbers: highlights_line_numbers,
        language: language
      # last_modified_at: time(last_modified_at)
    end
    hash
  end

  def code_search_result_item_hash(result, options)
    options = Api::SerializerOptions.from(options)
    repo = result["_model"]
    file_info = result["_source"]
    file_path = file_info["path"]
    blob_sha = file_info["blob_sha"]
    commit_sha = file_info["commit_sha"]

    file_name = file_info["filename"]
    file_path = [
      file_path,
      file_name
    ].reject(&:blank?).join("/").delete_prefix("/")

    hash = {
      name: file_name,
      path: file_path,
      sha: blob_sha,
      url: encoded_content_url("/repositories/#{repo.id}/contents/", file_path, { ref: commit_sha }),
      git_url: url("/repositories/#{repo.id}/git/blobs/#{blob_sha}"),
      html_url: encoded_html_url(repo.permalink, "/blob/#{commit_sha}/#{file_path}"),
      repository: simple_repository_hash(result["_model"], options),
    }

    if options.accepts_semantic_version?("extended-search-results")
      file_size = file_info["file_size"]
      language = file_info["language"]
      last_modified_at = file_info["timestamp"]
      highlights_line_numbers = line_numbers(result)
      hash.update \
        file_size: file_size,
        line_numbers: highlights_line_numbers,
        language: language,
        last_modified_at: time(last_modified_at)
    end
    hash
  end

  def commit_search_result_item_hash(result, options)
    options = Api::SerializerOptions.from(options)

    repo = result["_model"]
    doc = result["_source"]

    commit = Commit.new(repo, {
      "oid" => doc["hash"],
    })

    {
      url: url("/repos/#{repo.name_with_owner_for_api(use: options[:serialize_login])}/commits/#{doc["hash"]}"),
      sha: doc["hash"],
      node_id: global_id_for(commit, options),
      html_url: "#{repo.permalink}/commit/#{doc["hash"]}",
      comments_url: url("/repos/#{repo.name_with_owner_for_api(use: options[:serialize_login])}/commits/#{doc["hash"]}/comments"),
      commit: {
        url: url("/repos/#{repo.name_with_owner_for_api(use: options[:serialize_login])}/git/commits/#{doc["hash"]}"),
        author: {
          date: doc["author_date"],
          name: doc["author_name"],
          email: doc["author_email"],
        },
        committer: {
          date: doc["committer_date"],
          name: doc["committer_name"],
          email: doc["committer_email"],
        },
        message: doc["message"],
        tree: {
          url: url("/repos/#{repo.name_with_owner_for_api(use: options[:serialize_login])}/git/trees/#{doc["tree_hash"]}"),
          sha: doc["tree_hash"],
        },
        comment_count: result["_comment_count"],
      },
      author: user_hash(User.find_by(id: doc["author_id"]), content_options(options)),
      committer: user_hash(User.find_by(id: doc["committer_id"]), content_options(options)),
      parents: doc["parent_hashes"].map do |hash|
        {
          url: url("/repos/#{repo.name_with_owner_for_api(use: options[:serialize_login])}/commits/#{hash}"),
          html_url: "#{repo.permalink}/commit/#{hash}",
          sha: hash,
        }
      end,
      repository: simple_repository_hash(repo, options),
    }
  end

  # Internal: Converts an array of results from the index into an array of hashes.
  # See http://git.io/eTeKGA for context
  def array_to_hash(source)
    result = []
    source.each do |a|
      result << { "text" => a }
    end
    result
  end

  # Internal: Serialize the highlights for the given search result in the
  # format appropriate for use in the 'text_matches' property of the JSON
  # response.
  #
  # result - The Hash containing a single search result.
  #
  # Returns an Array of Hashes.
  def text_matches(result)
    field_names_and_matches = result.fetch("highlight", [])

    field_names_and_matches.map do |field_name, matches|
      matches.map do |match|
        Api::Serializer::TextMatch.to_hash(result, field_name, match)
      end
    end.flatten.compact.uniq
  end

  # Takes the given string and replaces `\r` and `\r\n` with a single `\n`
  # character. Trailing whitepsace is also removed.
  #
  # str - The String to clean up.
  #
  # Returns a new string.
  #
  def cleanup_line_endings(str)
    str = str.rstrip
    str.gsub!(/\r\n?/m, "\n")
    str
  end

  # Internal: This method will return the Range of line numbers in the file
  # where the highlight is found.
  #
  # Returns a Range of line numbers in the file.
  #
  def line_numbers(result)
    file = cleanup_line_endings(result["_source"]["file"])
    highlights = result["highlight"]["file"]
    ln = []

    return ln if highlights.nil?

    highlights.each do |highlight|
      clean = cleanup_line_endings(highlight[:text])
      reg = Regexp.new(Regexp.escape(clean))

      char_offset = file.index(reg)
      if !char_offset.nil?
        first_line = file.slice(0, char_offset).count("\n")
        last_line = first_line + clean.count("\n")

        range = first_line..last_line
        ln << range
      end
    end

    ln
  end
end
