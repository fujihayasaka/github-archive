# typed: true
# frozen_string_literal: true

require "timestamp"

module Search
  include Kernel
  autoload :RateLimitRegistry, "search/rate_limit_registry"
  autoload :Types, "search/types"
  autoload :ClientTypes, "search/client_types"

  extend self

  USE_INDEX_LOW_QUEUE = Set.new(%w[bulk_issues bulk_projects bulk_pull_requests bulk_discussions bulk_releases code commit wiki])
  CODE_SEARCH_INDEXING_KEY = "enable_code_search_indexing" # allow indexing source code
  CODE_SEARCH_ENABLED_KEY  = "enable_code_search"          # allow searching source code

  # Public: Enqueue a background job that will add the resource identified by `type` and `id` to the search index.
  # if `:interval` (seconds) is specified in opts, then the job is enqueued using `enqueue_once_per_interval`
  def add_to_search_index(type, id, opts = {})
    if verbose_add_to_search_index_enabled?
      # Get the method/block that called add_to_search_index
      # so we can trace where requests are originating from.
      caller_location = caller_locations(1, 1)&.first
      GitHub.logger.info({
        "gh.elasticsearch.document.type" => type,
        "gh.elasticsearch.document.id"   => id,
        "method"                         => "Search.add_to_search_index",
        "gh.elasticsearch.action"        => "index",
        "gh.elasticsearch.action.from"   => format_caller_location(caller_location),
      })
    end

    if type == "code"
      # Note in case this change is ever reverted and we resume running these
      # jobs outside of GHES:
      #
      # To help counteract automated crawling of code search results to find
      # API tokens and other secrets, we introduced a delay of 1 minute to
      # search indexing job for for all repositories with
      # `AddToSearchIndexJob.enqueue_once_per_interval([type, id, opts], interval: 60)`
      # _when the type was `code` and we were not in GHES_.
      # Removing this gate alone will not restore that functionality.
      return unless GitHub.use_elastomer_code_search?
    end

    queue = opts.delete(:queue)
    interval = opts.delete(:interval).to_i
    timestamp = Timestamp.from_time(Time.now.utc)
    opts = {
      "submitted_at" => timestamp,
      "request_id" => GitHub.context[:request_id],
    }.compact.merge(opts)
    opts["guid"] = AddToSearchIndexJob.guid(type, id, opts)

    options = {}

    if queue || USE_INDEX_LOW_QUEUE.include?(type)
      options[:queue] = queue ? queue : "index_low"
    end

    if interval > 0
      AddToSearchIndexJob.enqueue_once_per_interval(args: [type, id, opts], interval: interval, unique_id: opts["guid"])
    elsif Aggregator.instance.enabled?
      Aggregator.instance.enqueue(AddToSearchIndexJob, [type, id, opts], options)
    else
      AddToSearchIndexJob.set(options).perform_later(type, id, opts)
    end
  end

  # non-printable ASCII characters
  NON_PRINTABLE = /[\x00-\x08\x0B\x0C\x0E-\x1F]/

  # Public: Sanitize text for a Lucene index by removing non-printable
  # characters.
  #
  # text - The String text to sanitize.
  #
  # Returns the sanitized String.
  def sanitize(text)
    text = text.to_s
    text.gsub(NON_PRINTABLE, "")
  rescue ArgumentError
    encoding = text.encoding.to_s
    text = GitHub::Encoding.transcode(text, encoding, "UTF-8")
    text.gsub(NON_PRINTABLE, "")
  end

  # Public: Take a chunk of markdown text and remove all markdown syntax
  # leaving only the plain text.
  #
  # text - The String text to clean of markdown syntax.
  #
  # Returns the plain-text String.
  #
  def clean_markdown(text)
    text = text.to_s
    return text if text.empty?

    text = ERB::Util.html_escape(text)

    replace_map = {}
    ERB::Util::HTML_ESCAPE.each_pair do |_key, value|
      replace_map[value] = " "
    end
    reg_exp = Regexp.new(replace_map.keys.map { |x| Regexp.escape(x) }.join("|"))

    text = text.gsub(reg_exp, replace_map)
    text = ActionView::Base.full_sanitizer.sanitize(text)
    CommonMarker.render_doc(text, :DEFAULT, %i[strikethrough table]).to_plaintext
  end

  # Public: Take a chunk of markdown text and remove all markdown syntax
  # leaving only the plain text; the plain text is then stripped of any
  # unprintable characters.
  #
  # text - The String text to clean of markdown syntax and sanitize.
  #
  # Returns the sanitized plain-text String.
  #
  def clean_and_sanitize(text)
    sanitize(clean_markdown(text))
  end

  # Public: The Lucene QueryParser applies special meaning to several
  # characters when it is parsing a query string. If these characters are used
  # inappropriately the query will produce an error. The solution is to escape
  # these characters before passing the query string to ElasticSearch.
  #
  # The following special characters will be escaped with a leading backslash
  # by this method:
  #
  #    + - & | / ! ( ) { } [ ] ^  ~ * ? : \
  #
  # The quote " character has been omitted from the list allowing the user to
  # use quotes in their queries.
  #
  # text - The String that will have special characters escaped.
  # all  - Force double quotes to be escaped as well.
  #
  # Examples
  #
  #   escape_characters( "foo & bar :baz -info" )
  #   #=> "foo \& bar \:baz \-info"
  #
  # Returns a new String with Lucene special characters escaped.
  #
  def escape_characters(text, all = false)
    if all
      text.to_s.gsub(/([#{Regexp.escape('+-&|/!()[]{}^~*?:"')}]|\\(.))/, '\\\\\1')
    else
      text.to_s.gsub(/([#{Regexp.escape('+-&|/!()[]{}^~*?:')}]|\\(?!"))/, '\\\\\1')
    end
  end

  # Internal: Add a value to the given key found in the filters hash. If there
  # is already a value stored at the key, then create an array to store both
  # values. If the value is already an array, then just append the new value
  # to the array.
  #
  # filters - The filters Hash to operate on.
  # key     - The key as a String or Symbol.
  # value   - The new value to add.
  #
  # Returns the filters Hash.
  #
  def add_value_to_filters(filters, key, value)
    if filters.key? key
      if filters[key].is_a? Array
        filters[key] << value
      else
        filters[key] = [filters[key], value]
      end
    else
      filters[key] = value
    end
    filters
  end

  # Internal: Look up the language name for a given language ID, or nil if none was found.
  #
  # id - The language ID
  #
  # Returns the language name.
  def language_name_from_id(id)
    return nil if id.nil?
    language = Linguist::Language.find_by_id(id)
    language && language.name
  end

  # Makes sure to display something nice if add_to_search_index is called from within a do-block,
  # and the class/method name can't be determined easily. In that case, we display the file name
  # instead. Easier to ctrl+f for add_to_search_index in a target file than to parse out the right calling
  # context if it can't be determined.
  def format_caller_location(entry)
    entry&.label&.start_with?("block") ? entry&.path&.split("/")&.last : entry&.label
  end

  def verbose_add_to_search_index_enabled?
    GitHub.add_to_search_index_verbose? || FeatureFlag.vexi.enabled?(
      :verbose_add_to_search_index_logging, default: false
    )
  end

end  # Search
