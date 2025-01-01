# typed: true
# frozen_string_literal: true

require "cgi"

module GitHub::HTML
  # Replace all code placeholders with the final HTML in a wiki.
  class ProcessWikiCodeBlocksFilter < ::HTML::Pipeline::Filter
    def call
      return doc if !result[:code_blocks] || result[:code_blocks].empty?
      text = html

      result[:code_blocks].each do |id, spec|
        text.gsub!(/(?:<p>)?#{id}(?:<\/p>)?/) do
          code = spec[:code]
          remove_leading_space(code, /^#{spec[:indent]}/m)
          remove_leading_space(code, /^(  |\t)/m)
          "\n<pre lang=\"#{spec[:lang]}\"><code>#{ERB::Util.force_escape(code)}</code></pre>\n"
        end
      end

      text
    end

    # Remove the leading space from a code block. Leading space
    # is only removed if every single line in the block has leading
    # whitespace.
    #
    # code      - The code block to remove spaces from
    # regex     - A regex to match whitespace
    def remove_leading_space(code, regex)
      if code.lines.all? { |line| line =~ /\A\r?\n\Z/ || line =~ regex }
        code.gsub!(regex, "")
      end
    end
  end
end
