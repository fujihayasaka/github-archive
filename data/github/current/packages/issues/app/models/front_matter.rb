# typed: true
# frozen_string_literal: true

class FrontMatter
  REGEX = /\A---\s*\n(.*?\n?)^---\s*$\n?/m

  def initialize(string)
    @string = string
  end

  def parsed_yaml
    return unless @string

    @parsed_yaml ||= begin
      match = @string.match(REGEX)

      unless match && match[1]
        return
      end

      config = nil

      begin
        config = YAML.safe_load(match[1])
      rescue Psych::BadAlias, Psych::DisallowedClass, Psych::SyntaxError => boom
        # Send user-created content with bad YAML syntax to the github-user bucket
        Failbot.report(boom, app: "github-user", content: match[0])
        return
      end

      config
    end
  end

  def body
    @string.gsub(REGEX, "")
  end
end
