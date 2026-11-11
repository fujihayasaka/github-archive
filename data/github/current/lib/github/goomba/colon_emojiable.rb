# typed: strict
# frozen_string_literal: true

module GitHub::Goomba::ColonEmojiable
  COLON_EMOJI_PATTERN = /:[\w+-]+:/

  sig { params(html: String).returns(T::Boolean) }
  private def probably_not_a_colon_emoji?(html)
    return false unless html.include?(":")
    return false unless match = html.match(COLON_EMOJI_PATTERN)

    pre_match = match.pre_match.strip
    post_match = match.post_match.strip

    leading_slash?(pre_match) ||
      preceeded_by_colon_emoji?(pre_match) ||
      not_preceeded_by_a_space?(pre_match, match)
  end

  sig { params(pre_match: String).returns(T::Boolean) }
  private def leading_slash?(pre_match) = pre_match.end_with?("/")

  sig { params(pre_match: String).returns(T::Boolean) }
  private def preceeded_by_colon_emoji?(pre_match)
    return false if pre_match.empty?

    pre_match.scan(COLON_EMOJI_PATTERN).size.positive? &&
      pre_match.end_with?(":") &&
      !pre_match.start_with?(":")
  end

  sig { params(pre_match: String, match: MatchData).returns(T::Boolean) }
  private def not_preceeded_by_a_space?(pre_match, match)
    !pre_match.empty? && !match.pre_match.end_with?(" ")
  end
end
