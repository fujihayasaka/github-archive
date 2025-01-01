# typed: true
# frozen_string_literal: true

module GitHub::HTML

  # The MarkupFilter wraps the GitHub::Markup gem and makes it usable in an
  # HTML::Pipeline. The only caveat with this filter is that it takes a
  # TreeEntry as the input.
  class MarkupFilter < Filter
    include GitHub::UTF8

    FILTERED_USER_CONTENT_PLACEHOLDER = "[FILTERED USER CONTENT]".freeze

    # Given a TreeEntry object, run the blob data through the Markup filter and
    # return the generated HTML.
    #
    # blob - A TreeEntry
    #
    # Returns the rendered HTML as a String.
    def self.html_from_blob(blob)
      self.to_html(nil, { blob: blob })
    end

    def self.cache_key(context)
      [
        ("plaintext" if context[:plaintext]),
        ("sourcepos" if context[:use_sourcepos]),
      ].reject(&:blank?).join(":")
    end

    attr_reader :blob

    # Construct a new markup filter that will process a TreeEntry via the
    # GitHub::Markup gem. The TreeEntry is passed into the filter through the
    # context via the :blob option. To skip the normal rendering path, use the
    # :plaintext context setting. When this is true, the normal markup
    # processing will be skipped and we simply HTML escape the blob data.
    #
    # doc     - not used
    # context - A Hash or nil
    # result  - A Hash or nil
    #
    def initialize(doc, context = nil, result = nil)
      super doc, context, result
    end

    # Internal: Called by the initializer to validate the inputs to the
    # filter. We ensure that a TreeEntry is passed in context[:blob].
    #
    # Raises an ArgumentError if the blob is invalid.
    def validate
      @blob = context.fetch(:blob, nil)
      raise ArgumentError, "expecting a TreeEntry in `context[:blob]`" unless @blob.is_a?(TreeEntry)

      super
    end

    # Render the blob using the GitHub::Markup gem. If the blob cannot be
    # rendered, then we HTML escape the blob data and return that instead.
    #
    # We set the `:rendered` flag to the name of the rendering engine used if
    # we successfully rendered the blog. If the blob could not be rendered,
    # then the flag is set to `false`.
    #
    # Returns the rendered HTML as a String that is marked html_safe.
    def call
      html = nil
      result[:rendered] = true
      markup_options = {
        commonmarker_opts: [:UNSAFE, :FOOTNOTES],
      }

      if context.fetch(:use_sourcepos, false)
        markup_options[:commonmarker_opts] << :SOURCEPOS
      end

      begin
        if !context[:plaintext] && self.class.can_render_blob?(blob)
          content, frontmatter = parse_frontmatter(blob.data, result)
          renderer = GitHub::Markup.renderer(blob.name, content, symlink: !!blob.symlink_source)

          html = if renderer
            result[:rendered] = renderer.name
            renderer.render(blob.name, content, options: markup_options).to_s.html_safe # rubocop:disable Rails/OutputSafety
          else
            content
          end

          html = EscapeHelper.safe_join([frontmatter, html]) if frontmatter
        end
      rescue StandardError => boom # rubocop:todo Lint/GenericRescue
        Failbot.report_user_error(boom)
      end

      if html.blank?
        result[:rendered] = false
        html = ERB::Util.force_escape(blob.data)
      end

      # force utf8 encoding on the returned value
      utf8(html)
    end

    def parse_frontmatter(content, result)
      frontmatter = result.delete(:frontmatter)
      return [content, nil] if frontmatter.nil?

      skip = result.delete(:frontmatter_skip)
      [content.slice(skip..-1), frontmatter]
    end

    # Public: Determine if we should try to render the blob
    #
    # Returns true if we can safely render the blob.
    def self.can_render_blob?(blob)
      blob.can_render? && blob.viewable?
    end
  end  # MarkupFilter
end  # GitHub::HTML
