# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Sanitize orphan hrefs
  #
  # Some renderers produce anchors with targets that do not exist in the
  # document, i.e., there is
  #
  #     <a href="#12345"></a>
  #
  # But there is no corresponding
  #
  #     <a id="12345"></a>
  #
  # or
  #
  #     <a name="12345"></a>
  #
  # There are a few problems with this. The first problem occurs when we're diffing.
  # Some .rst files contain orphan links because they were designed to work with
  # plugins, but we don't run any plugins. These orphan links are spurious when we
  # show a preview: They simply don't work. But when we diff, these hrefs show up
  # as changes, and we end up with a lot of "changed hrefs" in the rich diff that don't
  # show up as changes in the source diff.
  #
  # See https://github.com/github/github/issues/22621
  #
  # This filter looks for all such "orphan" hrefs and removes them.
  #
  # If context[:name_prefix] is specified, it will be used to find href
  # targets. For example, if context[:name_prefix] is "foo-", then <a
  # href="bar"> will be considered to be valid only if there is a <a
  # id="foo-bar"> element in the document.
  #
  # Disabled unless context[:sanitize_orphan_hrefs] is true.
  class OrphanHrefFilter < NodeFilter
    SELECTOR = Goomba::Selector.new("a")

    def self.cache_key(context)
      return unless context[:name_prefix]
      "href_name_prefix=#{context[:name_prefix]}"
    end

    def self.enabled?(context)
      context[:sanitize_orphan_hrefs]
    end

    def selector
      SELECTOR
    end

    def call(element)
      href = element["href"]
      return unless href && href.start_with?("#")
      target = href[1..-1]
      if prefix = context[:name_prefix]
        target = "#{prefix}#{target}"
      end

      @targets ||= element.document.name_set
      targets = @targets.merge(GitHub::Goomba::TableOfContentsFilter.generated_anchors(scratch))
      return if targets.include?(target) || targets.include?(Addressable::URI.unescape(target))

      element.remove_attribute("href")
      element
    end
  end
end
