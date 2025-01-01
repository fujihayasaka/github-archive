# typed: false
# frozen_string_literal: true

module WikiHelper
  include CurrentRepositoryInteractionsHelper

  def wiki_data(page, context = nil, current_user = nil)
    if context.is_a?(String)
      cache_key = [
        page.cache_key,
        context,
        wiki_prefix_on_relative_links?,
        ("secure-user-assets" if GitHub.flipper[:secure_user_assets].enabled?(current_repository.owner)),
      ].join(":")

      cached = GitHub.cache.get(cache_key)
      return rewrite_cached_user_assets(cached, current_user) if cached

      data = wiki_data!(page)
      expires_in = data.errored? ? 30.minutes : 0
      GitHub.cache.set(cache_key, data, expires_in)
      data
    else
      wiki_data!(page)
    end
  end

  def rewrite_cached_user_assets(cached, current_user)
    actor = current_user || User.ghost

    return GitHub::Unsullied::CachedEnterpriseAssetUrlRewriter.rewrite(cached, actor) if GitHub.storage_cluster_enabled?

    return GitHub::Unsullied::CachedDotcomAssetUrlRewriter.rewrite(cached) if actor && GitHub.flipper[:wiki_cached_page_url_rewriter].enabled?(actor)

    cached
  end

  def wiki_data!(page)
    page.data_html({
      prefix_relative_links: wiki_prefix_on_relative_links?,
      secure_user_assets: GitHub.flipper[:secure_user_assets].enabled?(current_repository.owner),
    })
  end

  # A relative link in a wiki (e.g. <a href="my-other-page">Other page</a>) will
  # break when viewed from a wiki's homepage. For example, the homepage of the
  # `github/github` repo's wiki is https://github.com/github/github/wiki, so
  # the relative link above would ordinarily come out to
  # https://github.com/github/github/my-other-page which is incorrect.
  #
  # To fix this we use this method to tell the HTML Pipeline to prefix relative
  # links with "wiki/" if we're viewing them from the home page. This leads to
  # the correct URL: https://github.com/github/github/wiki/my-other-page.
  def wiki_prefix_on_relative_links?
    return false if request.path != wikis_path

    # This is a special case. If the user has already included a trailing slash
    # in their URL (e.g. https://github.com/github/github/wiki/), then we don't
    # need to add another "wiki/" prefix because the browser will simply append
    # relative links to the URL with a trailing slash.
    return false if URI.parse(request.original_fullpath).path.end_with?("/")

    true
  rescue URI::InvalidURIError
    false
  end

  def wiki_preview?
    if @wiki_preview.nil?
      @wiki_preview = @page.name == "_Preview"
    end
    @wiki_preview
  end

  def writable_wiki?
    return false unless current_repository_writable?
    current_user_can_write_wiki?
  end

  # Displays the title of a GitHub::Unsullied::Page. If this is a preview, append a
  # 'preview' suffix to the real wiki name.  Don't worry about sanitizing
  # the title.  Wiki pages with no H1 are limited by supported characters,
  # and titles extracted from H1 are cleaned by the Sanitize gem.
  #
  # page - Optional GitHub::Unsullied::Page instance.  Taken from @page in the controller
  #        by default.
  #
  # Returns the String title for an HTML page.
  def wiki_page_title(page = @page)
    title = if page.name == "_Preview"
      "#{params[:wiki][:name]} (Preview)"
    else
      page.title.to_s.dup
    end
    title.strip!
    title
  end

  # Builds a GUID fit for a wiki atom feed.
  #
  # page   - A GitHub::Unsullied::Page instance.
  # commit - A ::Commit describing the commit the page was last updated.
  #
  # Returns a String GUID.
  def wiki_guid(page, commit = page.revision_oid)
    "http#{:s if GitHub.ssl}://%s%s/%s" %
      [GitHub.host_name, wiki_page_path(page), commit]
  end

  # Display wiki help by default if a user is logged in but has never dismissed
  # this help before.
  def autodisplay_wiki_help?
    logged_in? && !current_user.dismissed_notice?("wiki_help")
  end

  def wiki_page_deletable?(page)
    page.name !~ /^home$/i
  end
end
