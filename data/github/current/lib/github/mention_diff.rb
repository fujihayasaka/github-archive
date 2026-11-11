# typed: true
# frozen_string_literal: true

module GitHub
  class MentionDiff
    # Minimal pipeline to extract mentions from a comment.
    Pipeline = GitHub::Goomba::WarpPipe.new(
      input_filters: [
        GitHub::Goomba::MarkdownFilter,
      ],
      node_filters: [
        GitHub::Goomba::MentionFilter,
        GitHub::Goomba::TeamMentionFilter,
      ],
      output_filters: [
        GitHub::Goomba::GithubReferenceFilter,
      ],
      result_class: GitHub::HTML::Result,
    )

    # Public
    def initialize(old_text, new_text, context = {})
      @old = Pipeline.call(old_text.try { |t| t.dup.force_encoding("utf-8").scrub! }, context)
      @new = Pipeline.call(new_text.try { |t| t.dup.force_encoding("utf-8").scrub! }, context)
    end

    def added_users
      @added_users ||= Array(@new[:mentioned_users]) - Array(@old[:mentioned_users])
    end

    def removed_users
      @removed_users ||= Array(@old[:mentioned_users]) - Array(@new[:mentioned_users])
    end

    def added_teams
      @added_teams ||= Array(@new[:mentioned_teams]) - Array(@old[:mentioned_teams])
    end

    def removed_teams
      @removed_teams ||= Array(@old[:mentioned_teams]) - Array(@new[:mentioned_teams])
    end
  end
end
