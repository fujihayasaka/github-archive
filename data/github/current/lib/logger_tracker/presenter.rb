# typed: true
# frozen_string_literal: true

class LoggerTracker
  class Presenter
    def self.render_callsites(results, commit)
      # + keeps the string from being frozen
      list = +"<ul>"
      results.reduce(list) do |list, result|
        list << "<li><a href='https://github.com/github/github/blob/#{commit}/#{result.render}'>#{result.render}</a></li>"
      end
      list << "</ul>"
    end

    def self.render_callsites_markdown(results, commit)
      results.map do |result|
        "* [#{result.render}](https://github.com/github/github/blob/#{commit}/#{result.render})"
      end
    end
  end
end
