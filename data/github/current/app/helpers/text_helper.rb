# typed: false
# frozen_string_literal: true

require "erb"
require "html_truncator"

module TextHelper
  extend T::Sig
  include GitHub::HTML
  include Scientist

  # Default context hash for HTML filters.
  def default_html_filter_context
    {
      base_url: base_url,
      entity: try(:current_repository),
    }
  end

  # Internal: Set up the context hash for the SimplePipeline
  #
  # These values are necessary for the RelativeLinkFilter
  # (see lib/github/html/relative_link_filter.rb), which is
  # sometimes used in places other than the web, where all
  # these values and classes are present.
  #
  # Returns a hash with :path, :committish, and :view keys
  def basic_html_context
    path = committish = view = nil

    begin
      path = path_string
      committish = tree_name

      if @view_name
        view = @view_name
      else
        view = case controller
        when TreeController, FilesController
          :tree
        when BlobController
          :blob
        end
        view = :preview if params[:action] == "preview"
      end
    rescue NameError, NoMethodError  # if these classes or methods don't exist
      path = committish = view = nil
    end

    { path: path, committish: committish, view: view }
  end
  private :basic_html_context

  def github_flavored_markdown(text, context = {})
    markdown_pipeline(text, { cache: true }.merge(context))
  end

  # Render HTML from Markdown input. Supports a subset of GitHub Flavored
  # Markdown, excluding task lists and linked mentions.
  #
  #   text - The raw Markdown text as a String
  #   context - HTML filter context hash
  #
  # Returns formatted HTML String.
  def github_simplified_markdown(text, context = {})
    return "" if text.nil?

    if !text.valid_encoding? || text.encoding != Encoding::UTF_8
      text = text.dup.force_encoding("utf-8").scrub!
    end

    markdown = CommonMarker.render_html(text, [:UNSAFE, :GITHUB_PRE_LANG], %i[tagfilter table strikethrough autolink])
    GitHub::Goomba::SimplePipeline.to_html(markdown, context)
  end

  # Render HTML from Markdown input. Supports a subset of GitHub Flavored
  # Markdown, excluding task lists and linked mentions.
  #
  #   text - The raw Markdown text as a String
  #   context - HTML filter context hash
  #
  # Returns formatted HTML String.
  def github_card_markdown(text, context = {})
    return "" if text.nil?

    context = default_html_filter_context.merge(context)
    GitHub::Goomba::CardPipeline.to_html(text, context)
  end

  # Render HTML from Markdown input. Supports a subset of Markdown suitable for
  # issue/PR titles (currently, just `inline code`).
  #
  #   text - A single line of (issue/PR title) text as a String
  #
  # Returns escaped, html_safe, formatted HTML String.
  #
  # See GitHub::Goomba::TitleMarkdownFilter for details
  def title_markdown(text)
    @title_markdown_memoized ||= {}
    @title_markdown_memoized[text] ||= GitHub::Goomba::TitleMarkdownFilter.call(text)
  end

  # Render HTML from Git commit messages
  #
  #  text - A single line of text (Git commit message) as a String
  #
  # Returns escaped, html_safe, formatted HTML String.
  def commit_message_markdown(text)
    title_markdown(text)
  end

  # Process markdown input with our default Markdown pipeline filters. This
  # includes running basic filters for sanitization, image replacement, and
  # mentions.
  #
  #   text - The raw Markdown text as a String
  #   context - HTML filter context hash
  #     cache: whether to cache text result (default: false)
  #     gfm: whether GFM is enabled (default: true)
  #
  # Returns formatted HTML String.
  #
  # See Also
  #   https://docs.github.com/articles/github-flavored-markdown/
  def markdown_pipeline(text, context = {})
    return "" if text.nil?

    cache_setting = if context.fetch(:cache, false)
      prefix = [
        context.fetch(:gfm, true) ? "gfm" : "mkd",
        "v3",
      ].join(":")
      {
        use_cache: true,
        cache_prefix: prefix,
      }
    else
      { use_cache: false }
    end
    context = default_html_filter_context.merge(context)
    GitHub::Goomba::MarkdownPipeline.to_html(text, context, cache_settings: cache_setting)
  end

  # Sanitize HTML. See GitHub::HTML::SanitizationFilter for
  # more advanced usage.
  #
  #   html      - String or DocumentFragment to filter
  #   whitelist - Sanitize whitelist configuration hash
  #
  # Returns the sanitized HTML as a DocumentFragment.
  def sanitize_filter(html, whitelist = nil)
    SanitizationFilter.call(html, whitelist: whitelist)
  end

  # Strip all tags from the input document.
  #
  # Returns a HTML string. Note that the result is NOT html_safe since it may
  # contain reserved HTML characters.
  def strip_tags(html)
    sanitize_filter(html, HTML::Pipeline::SanitizationFilter::FULL).inner_text
  end

  # Strip all tags from the input document and collapse all whitespace into
  # single spaces.
  #
  # Returns a HTML string. Note that, like #strip_tags, above, the result
  # is NOT html_safe since it may contain reserved HTML characters.
  def strip_tags_and_collapse_whitespace(html)
    strip_tags(html).gsub(/\s+/, " ").strip
  end

  # Truncate HTML to max visible characters.
  #
  # html - String HTML or a Nokogiri container node.
  # max  - Maximum number of visible characters to include in the result.
  #
  # Returns the truncated HTML as a String. The markup is guaranteed to have no
  # block elements.
  def truncate_html(html, max)
    HTMLTruncator.new(html, max).to_html(wrap: false)
  end

  # Like link_to but handles markup that may include other <a> tags. When
  # existing <a> tags are detected, all text nodes not already contained in
  # an <a> tag are wrapped in a link to url.
  #
  # html  - The HTML markup to linkify as a String or DocumentFragment. May
  #         include other <a> tags.
  # url   - The URL destination of the link.
  # attrs - Additional attributes to add to the <a> tag.
  #
  # Returns a String with HTML markup.
  sig { params(html: String, url: String, attrs: T::Hash[Symbol, String]).returns(String) }
  def link_markup_to(html, url, attrs = {})
    # If the input is not html safe and/or doesn't include an anchor tag, we don't need to process any further.
    return linkify_with_context(html, url, attrs) unless safe_html_contains_anchor?(html)

    doc = GitHub::HTML.parse(html)
    process_markup_with_links(doc, url, attrs)
  end

  sig { params(html: String).returns(T::Boolean) }
  private def safe_html_contains_anchor?(html)
    html.html_safe? && html.include?("<a ")
  end

  # If this is rendering a commit message we iterate over the links in it and
  # make sure that links that are URLs within the commit message are updated to
  # point to the commit instead of the URL. We do this in a way that preserves
  # any links that are references to issue numbers of mentions but also handles
  # long URLs that have been truncated.
  #
  # NOTE: BOOSH was very confusing to me at first. It's just a
  # placeholder string that gets replaced with actual content in the body of
  # this method.
  BOOSH = GitHub::HTMLSafeString.make("<<BOOSH>>")
  sig do
    params(
      doc: Nokogiri::HTML::DocumentFragment,
      url: String,
      attrs: T::Hash[Symbol, String]
    ).returns(ActiveSupport::SafeBuffer)
  end
  private def process_markup_with_links(doc, url, attrs)
    ellipses_length = 3
    template = linkify_with_context(BOOSH, url, attrs)
    doc.xpath("descendant::text()").each do |node|
      if attrs[:class] == "message"
        anchor_text = doc.search("a").xpath("text()").text
        doc.css("a").each do |link|
          link["href"] = url if link["href"][0..anchor_text.length - ellipses_length] == anchor_text[0..-ellipses_length]
        end
      end
      next if node.xpath("ancestor::a[1]").any?
      linked_text = link_markup_text_node(node, template)
      node.replace(linked_text)
    end
    doc.to_html.html_safe # rubocop:disable Rails/OutputSafety
  end

  def linkify_with_context(html, url, attrs)
    return link_to(html, url, attrs) if respond_to?(:link_to)
    view_context.link_to(html, url, attrs)
  end

  # Sanitizes strings with embedded HTML hyperlinks to be safe for rendering into other components
  # such as flash alerts.
  #
  # html - The String including the hyperlinks or other HTML to sanitize.
  #
  # Returns a String with sanitized HTML markup.
  def sanitize_html(html)
    sanitize_filter(html, { elements: ["a"], attributes: { "a" => ["href"] } }).to_html.html_safe # rubocop:disable Rails/OutputSafety
  end

  # Internal: Convert a single text node to a link excluding any leading and
  # trailing space characters.  /cc https://github.com/github/github/issues/8176
  #
  # node     - A nokogiri text node object or a string.
  # template - The link markup template. This is just a string with an <a>
  #            that's wrapped around the text node given.
  #
  # Returns a string of HTML markup.
  def link_markup_text_node(node, template)
    text = node.to_s
    return text if text.strip.empty?
    pre, mid, post = text.match(/\A([ \t\n]+)?(.*?)([ \t\n]+)?\z/m).to_a[1..3]
    mid = template.sub("<<BOOSH>>") { mid.to_s }
    [pre, mid, post].compact.join("")
  end

  def formatted_repo_description(repository, limit: ::Repository::DESCRIPTION_CHAR_LIMIT)
    formatted_description_string(GitHub::Encoding.try_guess_and_transcode(repository.description), limit: limit)
  end

  def formatted_description_string(description, limit: 350)
    return "" if description.blank?
    formatted = GitHub::Goomba::DescriptionPipeline.to_html(description)
    HTMLTruncator.new(formatted, limit).to_html(wrap: false)
  end

  # Formats numbers less than nine into words
  def number_to_words(number)
    return number if number > 9
    @number_to_words ||= { 0 => "zero", 1 => "one",  2 => "two", 3 => "three", 4 => "four",
                           5 => "five", 6 => "six", 7 => "seven", 8 => "eight", 9 => "nine" }
    @number_to_words[number]
  end

  alias_method :formatted_gist_description, :formatted_repo_description

  def strip_tags_inlining_urls(html)
    # Rails' FullSanitizer is basically what we want, but it does not allow us
    # to provide a custom scrubber. (And we'd rather not implement our own
    # sanitizer just to customize the scrubber.) However, we don't have static
    # access to the sanitizer used by the `sanitize` helper method. So
    # instead, we're resolved to grabbing the safe_list_sanitizer directly
    # from the rails-html-sanitizer gem and hoping it continues to be the one
    # that Rails (and GitHub) uses for `sanitize` under the hood.
    Rails::Html::Sanitizer.safe_list_sanitizer.new.sanitize html,
      scrubber: TextOnlyWithUrlsScrubber.new
  end
  module_function :strip_tags_inlining_urls

  class TextOnlyWithUrlsScrubber < ::Rails::Html::TextOnlyScrubber
    def scrub(node)
      node.after(" at #{node['href']}") if link? node
      super
    end

    private

    def link?(node)
      node.name == "a" && node["href"].yield_self do |href|
        href.present? && href != "#" && !href.start_with?("javascript:")
      end
    end
  end
end
