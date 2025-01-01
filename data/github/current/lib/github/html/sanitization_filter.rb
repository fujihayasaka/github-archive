# typed: true
# frozen_string_literal: true

require "goomba"
require "scientist"

module GitHub::HTML
  # HTML filter with sanization routines and whitelists. This module defines
  # what HTML is allowed in user provided content and fixes up issues with
  # unbalanced tags and whatnot.
  #
  # See the Sanitize docs for more information on the underlying library:
  #
  # https://github.com/rgrove/sanitize/#readme
  #
  # Context options:
  #   :whitelist - The sanitizer whitelist configuration to use. This can be one
  #                of the options constants defined in this class or a custom
  #                sanitize options hash.
  #
  # The following keys are written to the result hash:
  #   :html_safe - A boolean flag to indicate that results from this filter
  #                are safe to use in html unescaped (safe to mark html_safe).
  class SanitizationFilter < ::HTML::Pipeline::SanitizationFilter
    MAX_ID_LENGTH = 50

    def call
      doc = ::HTML::Pipeline::SanitizationFilter.instance_method(:call).bind(self).call
      fix_list_items_nesting
      truncate_any_long_id_attributes
      result[:html_safe] = true
      doc
    end

    private

    # Find all elements that contain LIs but that are not UL/OL. Assume that
    # the LI elements ended up in this container by HTML parser mistake, and
    # extract them out of the container.
    #
    # This compensates for Nokogiri's inability to auto-close open elements
    # inside a LI when the parser encounters a `</LI>` tag.
    def fix_list_items_nesting
      while li = doc.at_xpath('.//*[name() != "ul" and name() != "ol"]/li')
        parent = li.parent
        pos = parent.children.index(li)
        nodes = parent.children[pos..-1]
        parent.after(nodes)
      end
    end

    def truncate_any_long_id_attributes
      doc.xpath("*[@id]").each do |element|
        element["id"] = element["id"][0...MAX_ID_LENGTH]
      end
    end
  end
end
