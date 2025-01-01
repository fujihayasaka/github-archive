# typed: false
# frozen_string_literal: true

require "set"
require "nokogiri"

# Markup aware HTML truncator.
#
# - Truncates based on visible (text node) character length.
# - If `strip_block_elements` is `true`, strips block elements but not their content (<h1>, <ul>, etc).
# - Allows emoji and small images through as is.
# - Does not allow images larger than 20x20px.
# - Strips email replies ("Show quoted text")
# - If `preview_img_filter` is a hash that specifies the attributes we are looking for in a preview image. Ex { min_width: 300, max_height: 240 }
# - If `keep_svg_elements` is true, keeps the children of svg elements.
# - If `strip_heading_elements` is true, strips heading elements but not their content (<h1>, <h2>, <h3>).
# - If `strip_formatted_elements` is true, strips formatted elements but not their content (<div>, <pre>).
class HTMLTruncator
  include GitHub::Encoding

  def initialize(doc, max, strip_block_elements: true, strip_heading_elements: false, keep_svg_elements: false, strip_formatted_elements: false, preview_img_filter: {})
    @max = max
    @strip_block_elements = strip_block_elements
    @strip_heading_elements = strip_heading_elements
    @keep_svg_elements = keep_svg_elements
    @strip_formatted_elements = strip_formatted_elements
    @preview_img_filter = preview_img_filter

    @html_safe = if doc.is_a?(String)
      doc.html_safe?
    else
      # Assume it's been through HTML::Pipeline if it's a Nokogiri node.
      # Or if doc is nil the truncator will output a known safe value of `"<p></p>"`.
      true
    end

    @src = if doc.nil?
      Nokogiri::HTML::DocumentFragment.parse("")
    elsif doc.is_a?(String)
      Nokogiri::HTML::DocumentFragment.parse(doc)
    else
      doc
    end

    @preview_img_path = get_preview_img
    @dest = Nokogiri::HTML::DocumentFragment.parse("<p></p>")
    @length = truncate(@src, @dest.child, 0)
  end

  # Maximum number of visible characters to allow through.
  attr_reader :max

  # The number of visible characters added to the result document. This value
  # will never exceed max.
  attr_reader :length

  # The path to a potential preview image
  attr_reader :preview_img_path

  # Truncated HTML as a DocumentFragment.
  def document
    @dest
  end

  # Truncated HTML as a String.
  def to_html(wrap: true)
    html = if wrap
      document.to_html
    else
      document.child.inner_html
    end

    if @html_safe
      html.html_safe # rubocop:disable Rails/OutputSafety
    else
      html
    end
  end

  # The truncated portion of the original document as a DocumentFragment.
  def remaining
    @src
  end

  # List of elements that are allowed through. Other elements are traversed and
  # their text is included but the elements are stripped.
  ALLOWED = %w[a b i q em strong code tt ins del span sup sub var g-emoji].to_set
  PREVENT = %w[table tracking-block].to_set
  FORMATTED = %w[div pre].to_set
  ALLOWED_IMG_CLASS = %w[emoji octicon].to_set
  POSSIBLE_IMG_TAG = %w[img svg picture].to_set

  # List of classes that are not allowed through.
  BADCLASS = %w[email-hidden-toggle email-hidden-reply]

  def get_preview_img
    return nil if @preview_img_filter.empty?
    img_path = nil
    # find possible image-like paths and find the first one that matches the filter conditions
    POSSIBLE_IMG_TAG.each do |tag|
      @src.search(tag).map do |img|
        if img["src"].present?
          width_check = @preview_img_filter[:min_width].present? ? img["width"].to_i >= @preview_img_filter[:min_width].to_i : true
          height_check = @preview_img_filter[:max_height].present? ? img["height"].to_i <= @preview_img_filter[:max_height].to_i : true

          img_path = img["src"] if width_check && height_check
          # remove the image to ensure we won't show the same image twice
          img.remove
          break if img_path.present?
        end
      end
    end
    img_path
  end

  # Copy nodes from the source document to the dest document by visiting each
  # node in document order until the max character limit is exceeded. Only text
  # node values count toward the character limit.
  def truncate(src, dest, len)
    return len if len >= @max

    next_sibling = src.next_sibling
    case
    when src.element?
      if BADCLASS.include?(src["class"])
        # do nothing
      elsif POSSIBLE_IMG_TAG.include?(src.name.downcase)
        # for images, allow emoji and anything with a smallish width through as
        # is. other images are allowed through but their height and width is
        # adjusted.
        if allowed_image?(src) || badge_image?(src)
          attributes = src.attributes
          node = dest.document.create_element(src.name, attributes)
          if @keep_svg_elements && src.name.downcase == "svg" && !src.children.empty?
            src.children.each do |child|
              child_node = dest.document.create_element(child.name, child.attributes)
              node.add_child(child_node)
            end
          end
          dest.add_child(node)
          len += 1
        end
      elsif allowed_element?(src.name.downcase)
        # copy elements on the allowed list into the dest document
        src_name = src.name
        if @strip_heading_elements && (src_name.downcase == "h1" || src_name.downcase == "h2" || src_name.downcase == "h3")
          src_name = "p"
        end
        node = dest.document.create_element(src_name, src.attributes)
        node = dest.add_child(node)
        len = truncate(src.child, node, len) if src.child
      elsif src.child && !PREVENT.include?(src.name.downcase)
        # traverse into other elements but do not copy the element itself
        len = truncate(src.child, dest, len)
      end

    when src.text?
      # copy as much of the text node value as we can fit
      take = @max - len
      if take > 0
        text = try_guess_and_transcode(src.content)

        # Compact whitespace from text unless we're inside a <pre>, where spaces matter
        # https://developer.mozilla.org/en-US/docs/Web/HTML/Element/pre
        if @strip_block_elements || src.ancestors.none? { |el| el.name.downcase == "pre" }
          text = text.gsub(/[ \t\r\n]{2,}/, " ")
        end

        used = text[0, take]
        len += used.length
        if used.length < text.length
          grab = used.length <= 3 ? used.length - 1 : 3
          src.content = "…#{used[-grab..-1]}#{text[take, text.length]}"
          used = "#{used[0...-grab]}…"
        else
          src.remove
        end
        node = dest.document.create_text_node(used.to_s)
        node = dest.add_child(node)
      end
    else
      # traverse into other stuff like document fragments
      len = truncate(src.child, dest, len) if src.child
    end

    # if we get here the current node, all children, and preceding nodes in
    # document order have been fully processed.
    if len < @max
      src.remove
      # remove any empty a tags, since uploaded images often are wrapped in a tags
      dest.search("a:empty").each do |a|
        a.remove
      end
      len = truncate(next_sibling, dest, len) if next_sibling
    end

    len
  end

  # Determine if an image element should be allowed through.
  #
  # Returns true for allowed image classes and images that have a width or height of 20 pixels or less.
  def allowed_image?(node)
    ALLOWED_IMG_CLASS.include?(node["class"].to_s) ||
      (node["height"] && node["height"].to_i <= 20) ||
      ((node["width"] && node["width"].to_i <= 20) &&
       (node["height"].nil? || node["height"].to_i <= 20))
  end

  def badge_image?(node)
    node["data-canonical-src"].to_s.include?("badge") && # generally accommodate badges
    (node["height"].nil? || node["height"].to_i <= 20) # an attempt at not having giant pictures of badgers
  end

  def allowed_element?(name)
    return true if ALLOWED.include?(name)
    return false if @strip_block_elements

    return false if @strip_formatted_elements && FORMATTED.include?(name)

    true
  end
end
