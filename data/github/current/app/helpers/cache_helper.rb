# typed: false
# frozen_string_literal: true

# Handle returning cache keys for various fragment caches throughout the views
# Cache keys should be human readable whereever possible, though they should be under
# 250 characters to keep Memcache happy.
module CacheHelper

  # Used in app/views/gist/_snippet.html.erb for any gist snippets rendered
  #
  # gist - The gist we're caching the snippet for
  # blob - The blob in question, can be nil when we can't read it via GitRPC
  def gist_snippet_cache_key(gist, blob)
    [
      "gist:v4:snippet",
      gist.cache_key,
      blob.try(:name),
      blob.try(:oid),
    ]
  end

  def read_fragment(*args)
    controller.read_fragment(*args)
  end

  def write_fragment(*args)
    controller.write_fragment(*args)
  end

  # Public: Fetch fragment from cache or generate a client side include for
  # the client to fetch.
  #
  # As a debugging feature, adding ?_skipinclude=1 to any URL will force any
  # fragments to stay in their loading state. This is useful testing the loading
  # styles.
  #
  # poll      - Boolean should use polling behavior against src (default: false)
  # cache_key - String cache key to attempt to fetch
  # src       - String path to fetch fragment from if uncached
  # options   - Hash of options to pass along to the <include-fragment> tag
  # block     - Yields inner HTML of <include-fragment> tag
  #
  # Returns String of cached HTML or <include-fragment> tag.
  def include_cached_fragment(poll: false, cache_key: nil, src:, **options, &block)
    src = skipmc_url(src)
    skip = params[:_skipinclude]
    if cache_key && !skip && html = read_fragment(cache_key)
      html.html_safe # rubocop:disable Rails/OutputSafety
    else
      options = options.reverse_merge((skip ? :_src : :src) => src)

      # ViewComponents don't support the `class` attribute, so we need to
      # convert it to `classes` instead.
      if options[:class]
        options[:classes] = options[:class]
        options.delete(:class)
      end

      component = poll ? GitHub::PollIncludeFragmentComponent : Primer::Alpha::IncludeFragment

      render(component.new(**options), &block)
    end
  end

  # Append a skipmc=1 query parameter to the URL if the page was loaded with
  # skipmc. This is helpful for breaking caches not directly included on the
  # page, but loaded from other URLs via AJAX.
  #
  # url - The String to which we possibly append ?skipmc=1.
  #
  # Returns a URL String.
  def skipmc_url(url)
    return url unless params[:skipmc]
    parsed = Addressable::URI.parse(url)
    query = parsed.query_values || {}
    return url if query.key?("skipmc")
    parsed.query_values = query.merge(skipmc: 1)
    parsed.to_s
  end
end
