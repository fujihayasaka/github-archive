# typed: true
# frozen_string_literal: true

module GitHub::HTML
  class WikiSanitizationFilter < ::HTML::Pipeline::SanitizationFilter
    # Default allowlisted elements.
    EXTRA_ELEMENTS = %w[abbr acronym address caption
      cite col colgroup dfn dir menu s span
      strike u picture source]

    CLASS_ALLOWLIST = %w(anchor internal absent present octicon octicon-link)

    TRANSFORMERS = [
      lambda do |env|
        node = env[:node]
        return unless node["class"]
        node["class"] = node["class"].split(/\s+/).select do |c|
          CLASS_ALLOWLIST.include?(c) || c.start_with?("language-")
        end.join(" ")
        node.delete("class") if node["class"].empty?
      end,
    ]

    # This is seriously the cleanest way to do a deep dup. Don't judge.
    # Since we're calling this from the execution context of `HTML::Pipeline`, where `ALLOWLIST` is
    # also defined, specify the original `ALLOWLIST` here to avoid bringing in the changes from HTML::Pipeline
    # (e.g. adding `attributes.all => 'id'`)
    ALLOWLIST = ::HTML::Pipeline::SanitizationFilter::ALLOWLIST.dup
    ALLOWLIST[:attributes] = ALLOWLIST[:attributes].each_with_object({}) do |(el, attrs), hash|
      hash[el] = attrs - %w(rel target)
    end
    ALLOWLIST.delete :transformers
    CUSTOM_ALLOWLIST = Marshal.load(Marshal.dump(ALLOWLIST))

    CUSTOM_ALLOWLIST[:elements]               += EXTRA_ELEMENTS
    CUSTOM_ALLOWLIST[:attributes][:all]       += %w(class)
    %w(a h1 h2 h3 h4 h5 h6).each do |tag|
      (CUSTOM_ALLOWLIST[:attributes][tag] ||= []) << "id"
    end
    # + keeps the string from being frozen
    CUSTOM_ALLOWLIST[:protocols]["a"]["href"] += [+"ftp", +"irc", +"apt"]
    CUSTOM_ALLOWLIST[:remove_contents]        += %w(style)
    CUSTOM_ALLOWLIST[:transformers]            = TRANSFORMERS

    def allowlist
      CUSTOM_ALLOWLIST
    end
  end
end
