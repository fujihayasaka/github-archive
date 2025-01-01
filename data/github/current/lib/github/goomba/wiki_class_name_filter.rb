# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class WikiClassNameFilter < InputFilter
    CLASS_ALLOWLIST = %w(anchor internal absent present octicon octicon-link)

    def call(input)
      return "" if input.blank?
      doc = Goomba::DocumentFragment.new(input)
      doc.select("*[class]").each do |node|
        node["class"] = node["class"].split(/\s+/).select do |c|
          CLASS_ALLOWLIST.include?(c) || c.start_with?("language-")
        end.join(" ")
        node.remove_attribute("class") if node["class"].empty?
      end

      doc.to_html
    end
  end
end
