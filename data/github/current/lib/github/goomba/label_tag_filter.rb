# typed: true
# frozen_string_literal: true

#
# Matches links to labels and converts them to a Primer-style HTML element label <a> tag.
#
# Link target references
# ======================
#
# Link target references are transformed by adding an attribute to the <a>
# tag. Given input like this:
#
#   <a href="https://github.com/github/github/labels/bug">https://github.com/github/github/labels/bug</a>
#
# The following output will be given, ignoring whitespace differences:
#
#   <gh:label-mention
#      permalink="https://github.com/github/github/labels/bug"
#      text="🐛 Bug"
#      label="bug">
#   </gh:label-mention>
#
# The tag is changed by replacing the content, and adding the `gh:label`
# attribute.
#
# The 'nwo' element of the JSON object is the full nwo parsed from the URL,
# and is always present.
#
# The 'label' element is likewise parsed from the URL and read via ActiveRecord, as is the color.
# The 'style' attribute is added to the tag to affect the CSS variables of the rendered label.
# The 'class' attribute contains standard Primer CSS classes for user-generated labels.
#
module GitHub::Goomba
  class LabelTagFilter < NodeFilter

    def selector
      Goomba::Selector.new(match: "a[href^='#{GitHub.url}']")
    end

    def call(node)
      return unless repository

      inner_html = node.inner_html
      return unless node["href"] == inner_html

      href = node["href"]

      if md = href.match(permalink_regex)
        # TODO: Properly support renamed repos here
        # Only expand labels if the repo is the one being linked to
        return unless repository.name_with_owner == md[:nwo]

        label_mention_tag(
          label: md[:label],
          permalink: href,
          text: inner_html,
        )
      end
    end

    # returns an html-safe gh:label-mention tag
    def label_mention_tag(label:, permalink:, text:)
      attrs = {
        label: label,
        permalink: permalink,
        text: text,
      }.reject { |_k, v| v.nil? }

      # passing nil for body ensures the closing tag remains
      ActionController::Base.helpers.content_tag("gh:label-mention", nil, attrs)
    end

    private

    def permalink_regex
      %r{
        \A
        https?://
        #{Regexp.escape(GitHub.host_name)}
        /
        (?<nwo>#{GitHub::HTML::IssueMentionFilter::NWO})
        /labels/
        (?<label>[a-zA-Z0-9_\-%20]+)
      }x
    end
  end
end
