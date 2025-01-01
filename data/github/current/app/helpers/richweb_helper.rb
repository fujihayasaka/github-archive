# typed: strict
# frozen_string_literal: true

# The RichwebHelper is made to give an easy to use helper across github pages
# unifying the rich web meta tags.
# Supports facebook's open graph You can read more https://developers.facebook.com/docs/opengraph/overview
# Supports twitter's cards https://dev.twitter.com/docs/cards
module RichwebHelper

  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::TextHelper

  MINIMUM_SEO_DESCRIPTION_LENGTH = 50
  FB_PAGE_ID = "262588213843476"
  SENTENCE_INCLUDES_FULL_STOP_REGEX = /\A.*[\.\?!]\z/

  sig { params(text: String).returns(String) }
  def truncate_text(text)
    truncate(text, length: 200)
  end

  # Twitter card helper to output the necessary meta tags for a twitter summary card
  #
  # options - a hash of opengraph properties
  #    :site        - The Twitter username of the owner of this card's domain.
  #    :card        - The card type (ie. summary, app, player, etc).
  #    :title       - The title of the object as it should appear in the graph
  #    :description - A short description of the object
  #    :image       - An image (optional)
  #
  # Returns a String of <meta> tags.
  sig { params(options: T::Hash[Symbol, T.untyped]).returns(String) }
  def twitter_card(options)

    # we need title and description
    return "" unless options[:title] && options[:description]

    # set defaults
    options = options.reverse_merge(type: "object", image: "#{GitHub.url}/opengraph.png")

    # When there is no custom image URL, use card type "summary"
    if options[:image].blank?
      options = options.reverse_merge(card: "summary")
    # When a custom image URL is provided but a card type is NOT provided, default to card type "summary_large_image"
    elsif options[:card].blank? && options[:image]
      options = options.reverse_merge(card: "summary_large_image")
    end

    options[:description] = truncate(options[:description], length: 200)

    html = []
    html << tag(:meta, name: "twitter:image",   content: options[:image]) if options[:image]
    html << tag(:meta, name: "twitter:site",        content: "@github")
    html << tag(:meta, name: "twitter:card",        content: options[:card])
    html << tag(:meta, name: "twitter:title",       content: options[:title])
    html << tag(:meta, name: "twitter:description", content: truncate_text(options[:description]))

    if options[:twitter_creator]
      html << tag(:meta, name: "twitter:creator",     content: options[:twitter_creator])
    end

    safe_join(html)
  end

  # Open Graph helper to output the necessary meta tags for any open graph object
  #
  # options - a hash of opengraph properties
  #    :type        - The type of the object, such as 'article'
  #    :image       - An image
  #    :title       - The title of the object as it should appear in the graph
  #    :url         - The canonical URL of the object, used as its ID in the graph
  #    :description - A short description of the object
  #
  # Returns a String of <meta> tags.
  sig { params(options: T::Hash[Symbol, T.untyped]).returns(String) }
  def opengraph(options)
    # set defaults
    options = options.reverse_merge(type: "object", image: "#{GitHub.url}/opengraph.png")
    description = truncate_text(options[:description]) unless options[:description].blank?

    html = []
    if options[:video_source] == "youtube"
      html << tag(:meta, property: "og:video",            content: "http://www.youtube.com/v/#{options[:video_id]}")
      html << tag(:meta, property: "og:video:secure_url", content: "https://www.youtube.com/v/#{options[:video_id]}")
      html << tag(:meta, property: "og:image",            content: options[:video_thumbnail])
    elsif options[:video_source] == "vimeo"
      html << tag(:meta, property: "og:video",            content: "http://vimeo.com/#{options[:video_id]}")
      html << tag(:meta, property: "og:video:secure_url", content: "https://vimeo.com/#{options[:video_id]}")
      html << tag(:meta, property: "og:image",            content: options[:video_thumbnail])
    end

    if options[:video_source] == "youtube" || options[:video_source] == "vimeo"
      html << tag(:meta, property: "og:video:width",      content: "1728")
      html << tag(:meta, property: "og:video:height",     content: "1080")
      html << tag(:meta, property: "og:video:type",       content: "application/x-shockwave-flash")
    end

    html << tag(:meta, property: "og:image", content: options[:image])
    html << tag(:meta, property: "og:image:alt", content: description) unless description.blank?
    if options[:image].to_s.start_with?(GitHub.og_image_generator_base_url)
      html << tag(:meta, property: "og:image:width", content: OpenGraph::IMAGE_WIDTH)
      html << tag(:meta, property: "og:image:height", content: OpenGraph::IMAGE_HEIGHT)
    end

    flavor = if serving_gist_standalone?
      "Gist"
    else
      "GitHub"
    end
    html << tag(:meta, property: "og:site_name",   content: flavor)
    html << tag(:meta, property: "og:type",        content: options[:type])

    html << tag(:meta, property: "og:title",       content: options[:title])       if options[:title]
    html << tag(:meta, property: "og:url",         content: options[:url])         if options[:url]
    html << tag(:meta, property: "og:description", content: description) unless description.blank?
    html << tag(:meta, property: "og:updated_time", content: options[:updated_time]) if options[:updated_time]
    html << tag(:meta, property: "og:author:username", content: options[:author]) if options[:author]

    if options[:type] == "article"
      html << opengraph_article(options)
    elsif options[:type] == "profile"
      html << opengraph_profile(options)
    end

    safe_join(html)
  end

  # Appends a full stop to a sentence if one isn't present.
  #
  # sentence - the String requiring a full stop.
  #
  # Returns the String (or nil if passed)
  sig { params(sentence: T.nilable(String)).returns(T.nilable(String)) }
  def add_full_stop_to(sentence)
    return unless sentence
    return sentence if sentence.match(SENTENCE_INCLUDES_FULL_STOP_REGEX)
    "#{sentence}."
  end

  # Open graph helper for generating the description for a page.
  #
  # title - the String or nil title for the content or page.
  # description - the String or nil description for the specific content.
  # meta_description - the String generic description for the page.
  #
  # Returns a description String.
  sig do
    params(
      title: T.nilable(String),
      description: T.nilable(String),
      meta_description: T.nilable(String)
    ).returns(T.nilable(String))
  end
  def opengraph_description(title, description, meta_description)
    return truncated_page_description if _page_description.present?

    if description.blank?
      meta_description
    elsif description.length < MINIMUM_SEO_DESCRIPTION_LENGTH
      "#{add_full_stop_to(description)} #{meta_description}"
    elsif title.present?
      "#{description} - #{title}"
    else
      "#{description}"
    end
  end

  # AdaptiveCard helper to output the content:source meta tag
  #
  # options - a hash of opengraph properties
  #    :adaptivecard - The URL to the AdaptiveCard JSON object
  #
  # Returns a String of <meta type="content:source"> tags.
  sig { params(options: T::Hash[Symbol, T.untyped]).returns(String) }
  def adaptivecard(options)
    html = []
    html << tag(:meta, property: "content:source", content: options[:adaptivecard]) if options[:adaptivecard]
    safe_join(html)
  end

  private

  # Open graph helper for outputing the necessary tags for an article object
  #
  # options - a hash of opengraph properties
  #    all the options from `opengraph` and
  #    :section   - The section of your website to which the article belongs, such as 'Lifestyle' or 'Sports'
  #    :published - A time representing when the article was published
  #    :modified  - A time representing when the article was last modified
  #
  # Returns a String of <meta> tags.
  sig { params(options: T::Hash[Symbol, T.untyped]).returns(String) }
  def opengraph_article(options)
    html = []
    html << tag(:meta, property: "article:author",         content: FB_PAGE_ID)
    html << tag(:meta, property: "article:publisher",      content: FB_PAGE_ID)
    html << tag(:meta, property: "article:section",        content: options[:section])   if options[:section]
    html << tag(:meta, property: "article:published_time", content: options[:published]) if options[:published]
    html << tag(:meta, property: "article:modified_time",  content: options[:modified])  if options[:modified]
    safe_join(html)
  end

  # Open graph helper for outputing the necessary tags for a profile object
  #
  # options - a hash of opengraph properties
  #    all the options from `opengraph` and
  #    :username   - A username for the person that this profile represents
  #
  # Returns a String of <meta> tags.
  sig { params(options: T::Hash[Symbol, T.untyped]).returns(String) }
  def opengraph_profile(options)
    html = []
    html << tag(:meta, property: "profile:username", content: options[:username]) if options[:username]
    safe_join(html)
  end

  # Generates the truncated, manually set description for a page.
  #
  # Returns a truncated page description String.
  sig { returns(T.nilable(String)) }
  def truncated_page_description
    truncate(_page_description, length: 512)
  end

  sig { returns(T.nilable(String)) }
  private def _page_description
    @page_description ||= T.let(nil, T.nilable(String))
  end

  # Delegate to super, which is defined on UserSessionDependency. Since this helper can be included in other modules
  # that don't include that dependency, this papers over by rescuing and returning false. Reported to Failbot so we
  # can fix any area that mistakenly calls this method. In the future, methods that depend on other
  # ApplicationController dependencies should be separated from these helpers.
  sig { returns(T::Boolean) }
  private def serving_gist_standalone?
    super
  rescue NoMethodError => e
    Failbot.report(e)
    false
  end
end
