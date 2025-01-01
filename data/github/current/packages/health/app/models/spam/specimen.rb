# typed: true
# frozen_string_literal: true

module Spam

  # Wrap up data that we're checking for Spamminess and provide methods
  # to process and query it for various conditions and matches and such.
  class Specimen
    attr_writer :clean_node, :node
    attr_accessor :data, :raw_data, :tags

    delegate :nothing_but_image_links?, to: :node

    def initialize(data)
      @raw_data = data.dup
      @data     = GitHub::SpamChecker.cleanup_text(@raw_data)
      @tags     = []
    end

    def clean_node
      @clean_node ||= node.clean_copy
    end

    def node
      @node ||= Spam::Node.new(data)
    end

    def text
      @text ||= clean_node.just_text
    end

    # Add things like "has many fake HTML elements"
    def tag(new_tag)
      tags << new_tag
    end

    # Return true if the Specimen has more than the minimum number of
    # links to the same URL.  The minimum defaults to 1.
    def has_repeated_links?(minimum = 1)
      urls = node.collect_link_urls
      # Ignore anchor links when counting
      urls = urls.group_by(&:to_s).reject { |k, _v| k =~ /^#/ }
      urls.any? { |_k, v| v.length > minimum }
    end

    # Return true if spammer is using long strings of <br> to scroll
    # competitors off the screen, or strings of encoded &nbsp; chars
    # to do the same.
    def uses_spacing_tricks?
      node.excessive_leading_blanks? ||
      clean_node.excessive_leading_brs? ||
      clean_node.excessive_trailing_brs?
    end
  end
end
