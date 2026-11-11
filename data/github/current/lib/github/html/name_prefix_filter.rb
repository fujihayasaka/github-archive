# typed: true
# frozen_string_literal: true

module GitHub::HTML
  # Prefix elements with `name`, `id`, `aria-labelledby`, or `aria-describedby` attributes to prevent DOM clobbering
  #
  # In some cases, browsers create global variables on `window` for named
  # elements, overriding previous values. For example, the following will break
  # all event handling:
  #
  #     <a name="addEventListener"></a>
  #
  # This filter prefixes all named elements so that they do not clash with
  # existing DOM properties.
  #
  # See https://github.com/github/github/issues/23103 for more information.
  class NamePrefixFilter < Filter
    DEFAULT_NAME_PREFIX = "user-content-"

    # context[:name_prefix] - set to false to disable name prefixing.
    def initialize(doc, context = nil, result = nil)
      context = (context || {}).reverse_merge name_prefix: DEFAULT_NAME_PREFIX
      super doc, context, result
    end

    def prefix
      context[:name_prefix]
    end

    def call
      return doc unless prefix

      doc.css("*[name], *[id], *[aria-labelledby], *[aria-describedby]").each do |element|
        %w(name id aria-labelledby aria-describedby).each do |attribute|
          value = element[attribute]
          next if !value || value.empty?
          element[attribute] = value.sub(/\A(#{prefix})?/, prefix)
        end
      end

      doc.to_html
    end
  end
end
