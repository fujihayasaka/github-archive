# typed: true
# frozen_string_literal: true

require "json"

# Heavily inspired by / copied from https://github.com/github/github/blob/d8c8f44a52e86511d225a25873ea4a723fecfc29/test/rubocop/cop/janky_formatter.rb#L8
module AdvisoryDB
  class JankyFormatter < RuboCop::Formatter::ProgressFormatter
    def report_offense(file, offense)
      root = File.expand_path(File.join(File.dirname(__FILE__), "../../../"))
      data = {
        suite: offense.cop_name,
        message: janky_offense_message(offense),
        name: offense.message,
        location: "#{file.sub("#{root}/", "")}:#{offense.line}",
        fingerprint: Digest::SHA256.hexdigest([offense.cop_name, file, offense.line.to_s].join("|")),
      }
      output.puts "===FAILURE===", JSON.dump(data), "===END FAILURE==="
      super
    end

    def janky_offense_message(offense)
      offense_message = message(offense)
      if valid_line?(offense)
        line = offense.location.source_line
        if offense.location.first_line != offense.location.last_line
          line += " ..."
        end
        highlight = "#{" " * offense.highlighted_area.begin_pos}#{"^" * offense.highlighted_area.size}"
        offense_message = [offense_message, line, highlight].join("\n")
      end
      offense_message
    end
  end
end
