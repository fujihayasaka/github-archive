# typed: true
# frozen_string_literal: true

module Repository::HovercardDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  include UserHovercard::SubjectDefinition

  requires_ancestor { Repository }

  def user_hovercard_parent
    async_organization.sync
  end

  HOVERCARD_CONTRIBUTION_WINDOWS = { day: 1.day, week: 1.week, month: 1.month }.freeze

  included do
    # rubocop:disable Lint/UnusedBlockArgument
    define_user_hovercard_context :owner, ->(user, viewer, descendant_subjects:) do
      T.bind(self, Repository)

      if readable_by?(viewer)
        Hovercard::Contexts::Custom.new("Owns this repository", "repo") if owner_id == user.id
      end
    end
    # rubocop:enable Lint/UnusedBlockArgument

    # rubocop:disable Lint/UnusedBlockArgument
    define_user_hovercard_context :contributions, ->(user, viewer, descendant_subjects:) do
      T.bind(self, Repository)

      next if user.private_profile_for?(viewer)
      next unless readable_by?(viewer)

      # the scope for the user commit contributions in this repo
      commit_contribution_scope = commit_contributions.where(user_id: user.id)
      next if commit_contribution_scope.none?

      # go through each window in order and choose the first that passes the commit cutoff
      fact = HOVERCARD_CONTRIBUTION_WINDOWS.lazy.map do |duration_name, duration|
        if commit_contribution_scope.where("committed_date > ?", duration.ago).any?
          " in the past #{duration_name}"
        end
      end.detect(&:present?)

      Hovercard::Contexts::Custom.new("Committed to this repository#{fact}", "git-commit")
    end
    # rubocop:enable Lint/UnusedBlockArgument

    # rubocop:disable Lint/UnusedBlockArgument
    define_user_hovercard_context :discussion_answers, ->(user, viewer, descendant_subjects:) do
      T.bind(self, Repository)

      next if user.private_profile_for?(viewer)
      next unless discussions_active?
      next unless readable_by?(viewer)

      answer_contribution_scope = discussion_comments.chosen_answers.for_user(user)
      total_repo_answers_by_user = answer_contribution_scope.count

      next if total_repo_answers_by_user.zero?

      repo_name = ["this repository", name_with_display_owner].min_by(&:size)

      # go through each window in order and choose the first that passes the cutoff
      potential_recent_messages = HOVERCARD_CONTRIBUTION_WINDOWS.lazy.map do |duration_name, duration|
        count = answer_contribution_scope.created_after(duration.ago).count
        if count > 0
          "Answered #{count} #{"discussion".pluralize(count)} in #{repo_name} in the past #{duration_name}"
        end
      end

      message = potential_recent_messages.detect(&:present?) || begin
        "Answered #{total_repo_answers_by_user} #{"discussion".pluralize(total_repo_answers_by_user)} in #{repo_name}"
      end

      Hovercard::Contexts::Custom.new(message, "check-circle")
    end
    # rubocop:enable Lint/UnusedBlockArgument

    # rubocop:disable Lint/UnusedBlockArgument
    define_user_hovercard_context :discussions_started, ->(user, viewer, descendant_subjects:) do
      T.bind(self, Repository)

      next if user.private_profile_for?(viewer)
      next unless show_discussions?
      next unless readable_by?(viewer)

      discussions_scope = discussions.authored_by(user)
      total_started = discussions_scope.count

      next if total_started.zero?

      repo_name = ["this repository", name_with_display_owner].min_by(&:length)

      # go through each window in order and choose the first that passes the cutoff
      potential_recent_messages = HOVERCARD_CONTRIBUTION_WINDOWS.lazy.map do |duration_name, duration|
        count = discussions_scope.created_since(duration.ago).count
        if count > 0
          "Started #{count} #{"discussion".pluralize(count)} in #{repo_name} in the past #{duration_name}"
        end
      end

      message = potential_recent_messages.detect(&:present?) || begin
        "Started #{total_started} #{"discussion".pluralize(total_started)} in #{repo_name}"
      end

      Hovercard::Contexts::Custom.new(message, "comment-discussion")
    end
    # rubocop:enable Lint/UnusedBlockArgument
  end
end
