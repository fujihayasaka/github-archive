# typed: true
# frozen_string_literal: true

class PullRequest
  # Modify a commit message by wrapping around 72 characters,
  # so it fits the convention of Git commit messages.

  class CommitMessageWrapper
    GIT_CONVENTION = 72
    BREAK_SEQUENCE = /\r?\n/

    attr_reader :commit_message

    def initialize(commit_message)
      @commit_message = commit_message
    end

    def wrap
      result = []
      fenced = T.let(false, T::Boolean)
      commit_message.split(BREAK_SEQUENCE).each do |line|
        if line.start_with?("```")
          fenced = !fenced
        end
        if fenced || line.size <= GIT_CONVENTION
          result << line
        else
          buf = "".dup
          line.split.each do |word|
            word = T.let(word, String)
            if (buf.size + word.size) > GIT_CONVENTION - 1 # 72 with space
              result << buf
              buf = word
            else
              buf << " " unless buf.empty?
              buf << word
            end
          end
          result << buf unless buf.empty?
        end
      end
      result.join("\n")
    end
  end
end
