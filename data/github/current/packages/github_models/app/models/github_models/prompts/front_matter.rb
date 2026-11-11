# typed: true
# frozen_string_literal: true

class GitHubModels::Prompts::FrontMatter
  REGEX = /\A---\s*\n(.*?\n?)^---\s*$\n?/m

  sig { params(content: T.nilable(String)).void }
  def initialize(content)
    @content = content
    @metadata = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
  end

  sig { returns(T.nilable(T::Hash[String, T.untyped])) }
  def metadata
    return unless @content

    @metadata ||= begin
      match = @content.match(REGEX)

      unless match && match[1]
        return
      end

      config = nil

      begin
        config = YAML.safe_load(T.must(match[1]))
      rescue Psych::BadAlias, Psych::DisallowedClass, Psych::SyntaxError => boom
        # Send user-created content with bad YAML syntax to the github-user bucket
        Failbot.report(boom, app: "github-user", content: match[0])
        return
      end

      config
    end
  end

  sig { returns(String) }
  def content
    return "" unless @content
    @content.gsub(REGEX, "")
  end
end
