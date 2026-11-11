# typed: true
# frozen_string_literal: true

module GitHub::HTML
  class ProcessWikiLinksFilter < ::HTML::Pipeline::Filter
    def page
      context[:page]
    end

    def version
      page.revision_oid
    end

    def wiki
      page.wiki
    end

    def dir
      ::File.dirname(page.path)
    end

    # Process all tags from the tagmap and replace the placeholders with the
    # final markup.
    def call
      return doc if !result[:wiki_links] || result[:wiki_links].empty?

      link_pattern = /(#{result[:wiki_links].keys.map { |name| Regexp.escape(name) }.join('|')})/

      # Nasty selector due to nokogiri bug:
      # https://github.com/sparklemotion/nokogiri/issues/572
      doc.xpath("./text()|.//text()").each do |node|
        content = node.to_html

        content.gsub!(link_pattern) do |id|
          if has_ancestor?(node, %w(pre code))
            # Replace original content if inside of a code block
            "[[#{result[:wiki_links][id]}]]"
          else
            process_tag(result[:wiki_links][id])
          end

        end

        node.replace(content)
      end
      doc
    end

    # Process a single tag into its final HTML form.
    #
    # tag       - The String tag contents (the stuff inside the double
    #             brackets).
    #
    # Returns the String HTML version of the tag.
    def process_tag(tag)
      if html = process_image_tag(tag)
        html
      elsif html = process_file_link_tag(tag)
        html
      else
        process_page_link_tag(tag)
      end
    end

    # Attempt to process the tag as an image tag.
    #
    # tag - The String tag contents (the stuff inside the double brackets).
    #
    # Returns the String HTML if the tag is a valid image tag or nil
    #   if it is not.
    def process_image_tag(tag)
      parts = tag.split("|")
      return if parts.size.zero?

      name  = parts[0].strip
      path  = if file = find_file(name)
        ::File.join wiki.base_path, file.path
      elsif name =~ /^https?:\/\/.+(jpg|png|gif|svg|bmp)$/i
        name
      end

      if path
        opts = parse_image_tag_options(tag)

        containered = false

        classes = [] # applied to whatever the outermost container is
        attrs   = [] # applied to the image

        if width = opts["width"]
          if width =~ /^\d+(\.\d+)?(em|px)$/
            attrs << %{width="#{width}"}
          end
        end

        if height = opts["height"]
          if height =~ /^\d+(\.\d+)?(em|px)$/
            attrs << %{height="#{height}"}
          end
        end

        if alt = opts["alt"]
          attrs << %{alt="#{alt}"}
        end

        attr_string = attrs.size > 0 ? attrs.join(" ") + " " : ""

        if opts["frame"] || containered
          classes << "frame" if opts["frame"]
          %{<span class="#{classes.join(' ')}">} +
          %{<span>} +
          %{<img src="#{path}" #{attr_string}>} +
          (alt ? %{<span>#{alt}</span>} : "") +
          %{</span>} +
          %{</span>}
        else
          %{<img src="#{path}" #{attr_string}>}
        end
      end
    end

    # Parse any options present on the image tag and extract them into a
    # Hash of option names and values.
    #
    # tag - The String tag contents (the stuff inside the double brackets).
    #
    # Returns the options Hash:
    #   key - The String option name.
    #   val - The String option value or true if it is a binary option.
    def parse_image_tag_options(tag)
      tag.split("|")[1..-1].inject({}) do |memo, attr|
        parts = attr.split("=").map { |x| x.strip }
        memo[parts[0]] = (parts.size == 1 ? true : parts[1])
        memo
      end
    end

    # Attempt to process the tag as a file link tag.
    #
    # tag       - The String tag contents (the stuff inside the double
    #             brackets).
    #
    # Returns the String HTML if the tag is a valid file link tag or nil
    #   if it is not.
    def process_file_link_tag(tag)
      parts = tag.split("|")
      return if parts.size.zero?

      name  = parts[0].strip
      path  = parts[1] && parts[1].strip
      path  = if path && file = find_file(path)
        ::File.join wiki.base_path, file.path
      elsif path =~ %r{^https?://}
        path
      else
        nil
      end

      if name && path && file
        %{<a href="#{::File.join wiki.base_path, file.path}">#{name}</a>}
      elsif name && path
        %{<a href="#{path}">#{name}</a>}
      else
        nil
      end
    end

    # Attempt to process the tag as a page link tag.
    #
    # tag       - The String tag contents (the stuff inside the double
    #             brackets).
    #
    # Returns the String HTML if the tag is a valid page link tag or nil
    #   if it is not.
    def process_page_link_tag(tag)
      parts = tag.split("|")
      parts.reverse! if page.format == :mediawiki

      name, page_name = *parts.compact.map(&:strip)
      tag_name = page_name || name

      return unless tag_name

      unescaped_tag_name = CGI::unescapeHTML(tag_name)
      cname = ::GitHub::Unsullied::Page.cname(unescaped_tag_name)

      if name =~ %r{^https?://} && page_name.nil?
        %{<a href="#{name}">#{name}</a>}
      else
        presence    = "absent"
        link_name   = cname
        page, extra = find_page_from_name(cname)
        if page
          link_name = ::GitHub::Unsullied::Page.cname(page.name)
          presence  = "present"
        end
        link = ::File.join(wiki.base_path, CGI.escape(link_name))
        %{<a class="internal #{presence}" href="#{link}#{extra}">#{name}</a>}
      end
    end

    # Find the given file in the repo.
    #
    # name - The String absolute or relative path of the file.
    #
    # Returns the GitHub::Unsullied::File or nil if none was found.
    def find_file(name)
      if name =~ /^\//
        wiki.files.find(name[1..-1], version)
      else
        path = dir == "." ? name : ::File.join(dir, name)
        wiki.files.find(path, version)
      end
    end

    # Find a page from a given cname.  If the page has an anchor (#) and has
    # no match, strip the anchor and try again.
    #
    # cname - The String canonical page name.
    #
    # Returns a GitHub::Unsullied::Page instance if a page is found, or an Array of
    # [GitHub::Unsullied::Page, String extra] if a page without the extra anchor data
    # is found.
    def find_page_from_name(cname)
      if page = wiki.pages.find(cname)
        return page
      end
      if pos = cname.index("#")
        [wiki.pages.find(cname[0...pos]), cname[pos..-1]]
      end
    end
  end
end
