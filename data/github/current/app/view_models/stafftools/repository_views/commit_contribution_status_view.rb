# typed: true
# frozen_string_literal: true

module Stafftools
  module RepositoryViews

    class CommitContributionStatusView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include Stafftools::StatusChecklist

      attr_reader :status

      def in_upstream_default_state
        defaults = CommitContribution.branches(status.commit.repository).join(", ")
        status_li(status.in_upstream_default?, "In #{defaults} branch: #{status.in_upstream_default?}")
      end

      def email_linked_state
        status_li(status.email_linked?, "Email linked to author: #{status.email_linked?}")
      end

      def repo_valid_state
        status_li(status.repo_valid?, "Repository valid (has forked, opened an issue, or has push access): #{status.repo_valid?}")
      end

      def internal_repo_state
        status_li(!status.internal_repo?, "Commit belongs to an internal repo (see github/profile#557): #{status.internal_repo?}")
      end
    end
  end
end
