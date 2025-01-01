# typed: true
# frozen_string_literal: true

class DiscussionOpTextFormatter
  sig { params(discussion: T.untyped).void }
  def initialize(discussion)
    @discussion = discussion
  end

  sig { returns(T.untyped) }
  def format
    return @body if defined?(@body)
    @body = "\n### Discussed in #{@discussion.url}\n\n"
    @body += "<div type='discussions-op-text'>\n\n"
    @body += "<sup>Originally posted by **#{@discussion.safe_user.display_login}** #{@discussion.created_at.strftime("%B %e, %Y")}</sup>\n"
    @body += @discussion.body if @discussion.body
    @body += "</div>"
  end
end
