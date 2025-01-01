# typed: false
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

require "cache_key_logging_denylist"
require "objspace"

# Helpers for rendering blob contents with the HTML pipeline
module BlobMarkupHelper
  BLOB_MARKUP_CACHE_VERSION = "v33"
  include Scientist
  include OcticonsHelper

  def format_readme_with_toc(readme, relative_paths: false, entity: nil, committish: nil, classes: "")
    if GitHub::HTML::MarkupFilter.can_render_blob?(readme) || readme.viewable?
      context = {}

      context[:path] = relative_paths ? nil : File.dirname(readme.path)
      context[:entity] = entity unless entity.nil?
      context[:committish] = committish unless committish.nil?
      context[:add_tabindex_to_headings] = true

      result = markup_blob(readme, context)
      output = result[:output]
      output = output.html_safe if result[:html_safe] # rubocop:disable Rails/OutputSafety

      if result[:rendered]
        output = formatted_blob_content output, classes
      else
        output = plaintext_blob_content output
      end

      [output, result[:toc_headers_hash]]
    end
  rescue StandardError => e # rubocop:todo Lint/RescueException
    failbot(e)
    [plaintext_blob(readme), nil]
  end

  # Renders the README for the current repository.
  #
  # Returns an HTML String. If the README can't be rendered, returns the blob
  # content as plaintext.
  def format_readme(readme, relative_paths: false, entity: nil, committish: nil, classes: "", view: nil)
    if GitHub::HTML::MarkupFilter.can_render_blob?(readme) || readme.viewable?
      context = {}
      context[:path] = relative_paths ? nil : File.dirname(readme.path)
      context[:entity] = entity unless entity.nil?
      context[:committish] = committish unless committish.nil?
      context[:view] = view unless view.nil?

      result = markup_blob(readme, context)
      output = result[:output]
      output = output.html_safe if result[:html_safe] # rubocop:disable Rails/OutputSafety

      if result[:rendered]
        formatted_blob_content output, classes
      else
        plaintext_blob_content output
      end
    end
  rescue => e # rubocop:todo Lint/RescueException
    failbot(e)
    plaintext_blob(readme)
  end

  # Renders a blob through the HTML Pipeline
  #
  # blob - An instance of TreeEntry
  #
  # Returns the rendered HTML and result if the blob is formattable, otherwise nil and an empty object.
  def format_blob_with_result(blob, context = {})
    return nil, {} unless GitHub::HTML::MarkupFilter.can_render_blob?(blob)
    result = markup_blob(blob, context)
    return nil, {} unless result[:rendered]
    output = result[:output]
    output = output.html_safe if result[:html_safe] # rubocop:disable Rails/OutputSafety
    [formatted_blob_content(output), result]
  end

  def format_blobs_with_results(blobs_with_context)
    return [] if blobs_with_context.empty?

    results = batch_markup_blobs(blobs_with_context)
    results.map do |result|
      output = result[:output]
      if !output.nil?
        output = output.html_safe if result[:html_safe] # rubocop:disable Rails/OutputSafety
        rich_text = result[:rendered] ? formatted_blob_content(output) : plaintext_blob_content(output)
      else
        rich_text = nil
      end

      { richtext: rich_text, result: result }
    end
  end

  # Internal: Given a blob (presumably a plaintext README), formats it to be displayed
  # with <pre> tags and linking any obvious URLs.
  def plaintext_blob(blob)
    plaintext_blob_content markup_blob_content(blob, plaintext: true, autolink: false)
  end

  # Public: Wrap the HTML blob content in an <article> with appropriate classes.
  #
  # Produces the following markup:
  #   <article class="markdown-body entry-content container-lg">
  #     CONTENT
  #   </article>
  def formatted_blob_content(html, classes = "")
    base_classes = "markdown-body entry-content container-lg"
    base_classes += " #{classes}" unless classes.blank?

    content_tag(:article, html, class: base_classes, itemprop: "text")
  end

  # Internal: Wrap the plaintext blob content in a <pre> tag
  #
  # Produces the following markup:
  #   <div class="plain"><pre>CONTENT</pre></div>
  def plaintext_blob_content(html)
    content_tag(:div, content_tag(:pre, html, style: "white-space: pre-wrap"), class: "plain")
  end

  # Internal: Process a blob through the HTML pipeline
  #
  # blob    - The TreeEntry to process.
  # context - Additional options to pass to the HTML pipeline.
  #
  # Returns a hash from the HTML pipeline
  def markup_blob(blob, context = {})
    should_cache = true
    if context[:data]
      blob = blob.dup.tap { |b| b.data = context[:data] }
      context.delete(:data)
      # This isn't a real blob with an OID. Presumably it's temporary (e.g.,
      # for rendering prose diff previews). Don't bother caching it.
      should_cache = false
    end

    context = blob_html_context(blob).update(context)
    cache_settings = {
      use_cache: should_cache,
      cache_prefix: blob_markup_cache_key,
      cache_result_keys: [:toc_headers_hash, :html_safe, :rendered, :output]
    }

    begin
      markup_blob!(blob, context, cache_settings: cache_settings)
    rescue Timeout::Error => e
      failbot(e)
      raise if context[:plaintext]
      # It took too long to render the markup. Let's just show a plaintext
      # version instead and cache it for a couple of minutes. Maybe something
      # will change that will let us render it without timing out later.
      markup_blob!(
        blob,
        context.merge(plaintext: true, autolink: false),
        cache_settings: cache_settings.merge(ttl: 2.minutes.to_i)
      )
    end
  end

  def markup_blob!(blob, context, cache_settings: {})
    start = GitHub::Dogstats.monotonic_time
    begin
      Timeout.timeout 5 do
        cache_settings = cache_settings[:use_cache] ? cache_settings : {}
        result = GitHub::Goomba::MarkupPipeline.call(nil, context, cache_settings: cache_settings)
        GitHub.dogstats.timing_since("blob.process.markup.success", start)
        # Only these fields are needed and we don't care about
        # things here like processed task list items.
        result.slice(:rendered, :html_safe, :output, :toc_headers_hash)
      end
    rescue Exception # rubocop:todo Lint/RescueException
      GitHub.dogstats.timing_since("blob.process.markup.error", start)
      raise
    end
  end

  def batch_markup_blobs(blobs_with_context)
    promises = blobs_with_context.map do |blob_with_context|
      if !blob_with_context[:blob].viewable?
        next Promise.resolve({ rendered: false, output: nil })
      end

      context = blob_with_context[:markup_context] || {}

      context = blob_html_context(blob_with_context[:blob]).update(context)
      context[:plaintext] = true unless GitHub::HTML::MarkupFilter.can_render_blob?(blob_with_context[:blob])
      cache_settings = {
        use_cache: true,
        cache_prefix: blob_markup_cache_key,
        cache_result_keys: [:toc_headers_hash, :html_safe, :rendered, :output]
      }

      GitHub::Goomba::MarkupPipeline.async_call(nil, context, cache_settings: cache_settings)
    end

    Promise.all(promises).then do |results|
      results.map do |result|
        result.slice(:rendered, :html_safe, :output, :toc_headers_hash)
      end
    end.sync
  end

  def blob_markup_cache_key
    prefix = [CacheKeyLoggingDenylist::BLOB_MARKUP_PREFIX,
      BLOB_MARKUP_CACHE_VERSION,
    ].join(":")
  end

  # Internal: Process a blob through the HTML pipeline and return the `output`
  #           from the result hash, marking the string `html_safe` if the
  #           pipeline sanitized the output.
  #
  # blob - An instance of Walker::CachedContent
  # context - Additional options to pass to the HTML pipeline
  #
  # Returns a String
  def markup_blob_content(blob, context = {})
    result = markup_blob(blob, context)
    output = result[:output]
    output = output.html_safe if result[:html_safe] # rubocop:disable Rails/OutputSafety
    output
  end

  # Public: Same as `markup_blob_content`, but return `nil` if the markup does
  # not succeed.
  #
  # blob - An instance of Walker::CachedContent
  # context - Additional options to pass to the HTML pipeline
  #
  # Returns a String or nil
  def markup_blob_content_if_successful(blob, context = {})
    result = markup_blob(blob, context)
    return unless result[:rendered]
    output = result[:output]
    output = output.html_safe if result[:html_safe] # rubocop:disable Rails/OutputSafety
    output
  end

  # Internal: *.rb.md style extensions.
  LITERATE_EXTENSIONS = { "rb" => "ruby" }

  # Internal: The context to use when rendering a blob through the HTML pipeline
  #
  # blob - An instance of Walker::CachedContent
  #
  # Returns a Hash
  def blob_html_context(blob)
    default_html_filter_context.merge(basic_html_context).tap do |context|
      context[:blob] = blob
      context[:name] = blob.path
      context[:entity] = blob.repository if blob.try(:repository).present?
      context[:anchor_icon] = octicon("link")

      context[:highlight] = "coffee" if blob.name =~ /litcoffee$/

      # allow "foo.coffee.md" or "foo.rb.md" to specify a default highlight
      segments = File.basename(blob.name).split(".")[1..-2]
      extension = segments.try(:last)

      if extension.present?
        context[:highlight] = LITERATE_EXTENSIONS[extension] || extension
      end
    end
  end
end
