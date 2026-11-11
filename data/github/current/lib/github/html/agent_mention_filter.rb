# typed: true
# frozen_string_literal: true

module GitHub::HTML
  class AgentMentionFilter < Filter
    # Reuse the same ignore list as user mentions so we skip code blocks, links, etc.
    IGNORE_PARENTS = ::HTML::Pipeline::MentionFilter::IGNORE_PARENTS

    # Matches:   "@claude[agent]", "(@Claude[Agent])", "text @codex[agent],"
    # Ignores:   "foo@claude[agent].com" (email), "@claude[bot]" (different tag),
    #            "@claude[agent" (unfinished bracket)
    AGENT_MENTION_BRACKET_PATTERN = /
      (?:^|[^a-zA-Z0-9_`])                 # beginning of string or non-word, non-` char
      (?<mention>@(?<token>[A-Za-z0-9][A-Za-z0-9\-_]*)\[(?i:agent)\]) # @slug[agent]
      (?=
        \.+[ \t\W]|                        # dots followed by space or non-word character
        \.+$|                              # dots at end of line
        [^0-9a-zA-Z_.`]|                   # non-word character except dot or `
        $                                  # end of line
      )
    /x.freeze

    # Fast, and cheap first check
    def self.likely_agent_mention?(text)
      text.downcase.include?("[agent]")
    end

    def self.mentioned_agents_in(text)
      patterns = [AGENT_MENTION_BRACKET_PATTERN]

      patterns.reduce(text) do |current, pattern|
        current.gsub(pattern) do |match|
          last_match = T.must(Regexp.last_match)
          token = last_match[:token]
          mention = last_match[:mention]
          yield match, token, mention
        end
      end
    end
  end
end
