# typed: true
# frozen_string_literal: true

module GitHub::HTML
  class WikiSanitizationFilter < ::HTML::Pipeline::SanitizationFilter
    # Default whitelisted elements.
    EXTRA_ELEMENTS = %w[abbr acronym address caption
      cite col colgroup dfn dir menu s span
      strike u picture source]

    CLASS_WHITELIST = %w(anchor internal absent present octicon octicon-link)

    TRANSFORMERS = [
      lambda do |env|
        node = env[:node]
        return unless node["class"]
        node["class"] = node["class"].split(/\s+/).select do |c|
          CLASS_WHITELIST.include?(c) || c.start_with?("language-")
        end.join(" ")
        node.delete("class") if node["class"].empty?
      end,
    ]

    # This is seriously the cleanest way to do a deep dup. Don't judge.
    # Since we're calling this from the execution context of `HTML::Pipeline`, where `WHITELIST` is
    # also defined, specify the original `WHITELIST` here to avoid bringing in the changes from HTML::Pipeline
    # (e.g. adding `attributes.all => 'id'`)
    whitelist = ::HTML::Pipeline::SanitizationFilter::WHITELIST.dup
    whitelist[:attributes] = whitelist[:attributes].each_with_object({}) do |(el, attrs), hash|
      hash[el] = attrs - %w(rel target)
    end
    whitelist.delete :transformers
    CUSTOM_WHITELIST = Marshal.load(Marshal.dump(whitelist))

    CUSTOM_WHITELIST[:elements]               += EXTRA_ELEMENTS
    CUSTOM_WHITELIST[:attributes][:all]       += %w(class)
    %w(a h1 h2 h3 h4 h5 h6).each do |tag|
      (CUSTOM_WHITELIST[:attributes][tag] ||= []) << "id"
    end
    # + keeps the string from being frozen
    CUSTOM_WHITELIST[:protocols]["a"]["href"] += [+"ftp", +"irc", +"apt"]
    CUSTOM_WHITELIST[:remove_contents]        += %w(style)
    CUSTOM_WHITELIST[:transformers]            = TRANSFORMERS

    def whitelist
      CUSTOM_WHITELIST
    end
  end
end
