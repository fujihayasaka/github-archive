# typed: true
# frozen_string_literal: true

class LoggerTracker
  class CodeownerIdentifier
    attr_reader :logger_calls, :codeowners

    def initialize(logger_calls = LoggerTracker::LOGGER_CALLS, codeowners = LoggerTracker::CODEOWNERS)
      @logger_calls = logger_calls
      @codeowners   = codeowners
    end

    def logger_calls_for_teams(teams, logger, local = true)
      teams.reduce({}) do  |team_map, team|
        logger.log("Looking for logger calls for team #{team}")
        files = LoggerTracker.call(owner: team, logger_calls: logger_calls, codeowners: codeowners, local: local)
        logger.log("Found #{files.size} logger call(s) for team: #{team}")
        if files.any?
          team_map[team] = {
            file_count: files.size,
            files: files.map(&:render)
          }
        end
        team_map
      end
    end

    def list_unique_codeowner_teams
      teams = T.let([], T::Array[String])
      ::File.open(codeowners, "r").each_line do |line|
        line = line.chomp
        next if line.empty? || line.match?(/[[:space:]]*#/)
        file_pattern, *owners = line.split(/[[:space:]]+/)
        next if file_does_not_log(file_pattern)
        teams += T.must(owners)
      end
      teams.uniq
    end

    def file_does_not_log(file)
      File.fnmatch("*node_modules/*", file) ||
        File.fnmatch("*vendor/*", file) ||
        File.fnmatch("*assets/*", file) ||
        File.fnmatch("*sorbet/*", file) ||
        File.fnmatch("*db/migrate/*", file) ||
        File.fnmatch("*public/*", file) ||
        File.fnmatch("*.ts", file) ||
        File.fnmatch("*.js", file) ||
        File.fnmatch("*.css", file)
    end
  end
end
