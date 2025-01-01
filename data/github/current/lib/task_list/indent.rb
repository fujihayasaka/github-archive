# typed: true
# frozen_string_literal: true

class TaskList
  class Indent
    def match(text, width)
      indent(dedent(text), width)
    end

    private

    def width(text)
      match = text.match(/\A\s+/)
      match ? match[0].size : 0
    end

    def dedent(text)
      text.gsub(/^\s{#{width(text)}}/, "")
    end

    def indent(text, width)
      text.gsub(/^/, " " * width)
    end
  end
end
