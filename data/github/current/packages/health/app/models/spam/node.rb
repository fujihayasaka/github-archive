# typed: true
# frozen_string_literal: true

module Spam
  class Node
    attr_writer :pipecleaned, :pipeline
    attr_accessor :noko, :raw_data

    def initialize(data)
      if data.is_a? Nokogiri::HTML::DocumentFragment
        @raw_data = data.to_html
        @noko = data
      else
        @raw_data = data.dup
        @noko = Nokogiri::HTML::DocumentFragment.parse(@raw_data)
      end
    end

    def clean_copy
      new_node = Spam::Node.new(pipecleaned)
      new_node.clean_fragment
      new_node
    end

    def pipecleaned
      @pipecleaned ||= pipeline.call(raw_data)[:output]
    end

    def pipeline
      @pipeline ||= HTML::Pipeline.new [
        GitHub::HTML::MarkdownFilter,
        HTML::Pipeline::SanitizationFilter,
      ], { liberal_html_tag: true }
    end

    # These are tags that we'll ignore instead of turning into spaces
    # when doing just_text, because they won't break up words that
    # the spammer wants visible and readable in the gist, so he will
    # insert them willy-nilly in the middle of words that we want to
    # retrieve as whole tokenizable words.
    NONSPACE_HTML5_TAGS = %w[a b basefont big center em fieldset font
      i img isindex label noframes noscript optgroup script small span
      strike strong style sub sup u
    ]

    # Return just the text elements smunged together
    def just_text
      the_text = "".dup
      noko.traverse do |element|
        if element.text?
          the_text << element.text
        else
          the_text << " " unless NONSPACE_HTML5_TAGS.include? element.name
        end
      end
      the_text.strip
    end

    ################################################################
    # Tasty Helper methods
    ################################################################
    NBSP = "\xC2\xA0" # "\u00A0" aka 194
    NBSP_AND_NEWLINE = "#{NBSP}\n?" # "\u00A0\n?" aka 194 160

    def whitespace_text_element?(element)
      element.text? && element.content =~ /\A(#{NBSP}|\s)+\z/m
    end

    def clean_elements(fragment, *name_list)
      fragment.traverse { |n| n.remove if name_list.include?(n.name) }
    end

    # Clean out the cruft trying to hide from us
    def clean_fragment(fragment = noko)
      @prev_el_was_whitespace = false
      fragment.traverse do |e|
        remove_element = false
        if this_el_is_whitespace = whitespace_text_element?(e)
          # Compress &NBSP; and tabs and spaces to one space
          e.content = " "

          # Toss any subsequent consecutive whitespace elements
          remove_element = @prev_el_was_whitespace
        end

        # Toss elements which don't mean anything without children
        remove_element ||= LONELY_HTML5_TAGS.include?(e.name) && e.children.empty?

        if remove_element
          # If we're removing the current element, we want to leave the state of
          # @prev_el_was_whitespace however it was coming in.
          e.remove
        else
          # If we're not removing this element, then set @prev_el_was_whitespace
          # to whatever is correct for *this* element, which will be the new
          # "previous element" that survived the culling.
          @prev_el_was_whitespace = this_el_is_whitespace
        end
      end

      # Return the fragment in case we're using it in an assignment
      fragment
    end

    LEADING_NBSP_LIMIT = 2
    LEADING_BR_LIMIT   = 6
    TRAILING_BR_LIMIT  = 6

    def excessive_leading_blanks?(fragment = nil)
      return false unless fragment ||= noko

      if fragment.children.count == 1 && fragment.children.first.name == "p"
        return excessive_leading_blanks?(fragment.children.first)
      end

      # Starts with a long series of encoded &nbsp;/NL pairs? Don't think so.
      breaks = 0
      fragment.traverse do |n|
        # Skip the 'self' node; it's tricky.
        next if n.name == "#document-fragment"
        # Only looking for contiguous &nbsp; elements at the open.
        break unless n.content =~ /\A\s*(#{NBSP_AND_NEWLINE})+/
        breaks += n.content.scan(/#{NBSP_AND_NEWLINE}/).count
        return true if breaks > LEADING_NBSP_LIMIT
      end
    end

    def excessive_leading_brs?(fragment = nil)
      return false unless fragment ||= noko

      # Pipeline likes to wrap up all our actual fragment in a top-level
      # paragraph. Recurse and return if that's the case here.
      if fragment.children.count == 1 && fragment.children.first.name == "p"
        return excessive_leading_brs?(fragment.children.first)
      end

      # Begins with a long series of <br> tags? Bzzzt.
      if (fragment.children.count > LEADING_BR_LIMIT) &&
         (fragment.children.to_a.first(LEADING_BR_LIMIT).all? { |n| n.name == "br" })
        true
      end
    end

    def excessive_trailing_brs?(fragment = nil)
      return false unless fragment ||= noko

      # Pipeline likes to wrap up all our actual fragment in a top-level
      # paragraph. Recurse and return if that's the case here.
      if fragment.children.count == 1 && fragment.children.first.name == "p"
        return excessive_trailing_brs?(fragment.children.first)
      end

      # Ends with a long series of <br> tags? Bzzzt.
      if (fragment.children.count > TRAILING_BR_LIMIT) &&
         (fragment.children.to_a.last(TRAILING_BR_LIMIT).all? { |n| n.name == "br" })
        true
      end
    end

    def collect_link_urls
      noko.search("a").collect { |j| j.attributes["href"] }.compact.collect { |j| j.value }
    end

    # For the given Nokogiri fragment (or our own Nokogiri node, if none
    # was passed in), return a Hash of all the fake HTML tags, along with
    # how many of each we saw.
    #
    # Returns: Hash
    def get_fake_tags(fragment = nil)
      return {} unless fragment ||= noko

      fake_tags = Hash.new(0)

      fragment.traverse do |n|
        next if Spam::Node::VALID_HTML5_TAGS.include? n.name
        fake_tags[n.name] += 1   # increment the count of this particular fake tag
      end
      fake_tags
    end

    def count_fake_tags(fragment = nil, verbose = false)
      fake_tags = get_fake_tags(fragment)
      puts "Found #{fake_tags.keys.count} fake tags: #{fake_tags.inspect}" if verbose
      fake_tags.keys.count
    end

    # Return true if the Nokogiri fragment consists of image links, and nothing
    # but image links.
    def nothing_but_image_links?(fragment = nil)
      # If we don't have a valid node passed in, and don't have one to start
      # with, we're doomed anyway.

      return false unless fragment ||= noko

      # Gonna chop it up, so let's make a working copy
      fragment = fragment.dup

      clean_elements(fragment, "br")
      return false unless fragment.children.present?

      # If there's only one child node left, and it's a content tag, recurse
      # with the child node and return with the output the recursion.
      if fragment.children.size == 1 && STRIP_HTML5_TAGS.include?(fragment.child.name)
        return nothing_but_image_links? fragment.child
      end

      # Otherwise return true if all the non-blank children are img links.
      fragment.children.reject { |c| whitespace_text_element?(c) }.all? do |n|
        children = n.children.reject { |c| whitespace_text_element?(c) }

        n.name == "a" &&
        children.any? &&
        children.all? { |child| child.name == "img" }
      end
    end

    # Not sure what to call these; but they're basically elements that are
    # not going to do anything if they're inserted without a close or with
    # no content other than whitespace. Spammers use some of them to try to
    # avoid content analysis.  It's a crude war here, and I'm experimenting.
    LONELY_HTML5_TAGS = %w[abbr acronym address area b blockquote body button
      caption center cite code col colgroup comment dd div dl dt em fieldset
      font form frame frameset h1 h2 h3 h4 h5 h6 head i iframe input label
      legend li link map menu meta noframes noscript ol option p param pre q
      s samp script select small span strike strong style sub sup table tbody
      td textarea tfoot th thead title tr tt u ul var]

    # List of tags that we'll strip away when looking to see if content has
    # nothing_but_image_tags? .
    STRIP_HTML5_TAGS = %w[b dd div dl dt em font h1 h2 h3 h4 h5 h6 i li p pre
      q small span strike strong sub sup td u]

    VALID_HTML5_TAGS = %w[a abbr acronym address applet area b base basefont
      bdo big blockquote body br button caption center cite code col colgroup
      comment dd del dfn dir div dl dt em fieldset font form frame frameset
      h1 h2 h3 h4 h5 h6 head hr html i iframe img input ins isindex kbd label
      legend li link map menu meta noframes noscript object ol optgroup option
      p param pre q s samp script select small span strike strong style sub sup
      table tbody td text textarea tfoot th thead title tr tt u ul var
      #document-fragment
    ]

  end
end
