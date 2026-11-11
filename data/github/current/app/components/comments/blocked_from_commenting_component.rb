# typed: true
# frozen_string_literal: true

module Comments
  class BlockedFromCommentingComponent < ApplicationComponent
    # repo_owner - the User or Organization who owns the repository where the comment would take place
    # code_of_conduct_url - optional String URL for the repository's code of conduct, if it has one
    def initialize(repo_owner:, code_of_conduct_url: nil)
      @repo_owner = repo_owner
      @code_of_conduct_url = code_of_conduct_url
    end

    private

    attr_reader :repo_owner, :code_of_conduct_url

    def render?
      repo_owner.present? && logged_in?
    end

    memoize def notifiable_block?
      repo_owner.organization? && org_block&.blocked_from_content # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    memoize def org_block
      IgnoredUser.blocked_by(repo_owner).blocking(current_user).first
    end

    def octicon
      notifiable_block? ? "circle-slash" : "lock"
    end

    memoize def blocked_from_org_content_url
      blocked_from_content = org_block&.blocked_from_content
      return unless blocked_from_content

      blocked_from_content.async_path_uri.sync.to_s
    end

    def message
      return "You can't perform this action at this time." unless notifiable_block?

      message_parts = ["You are blocked "]
      message_parts << "for #{distance_of_time_in_words_to_now(org_block.expires_at)} " if org_block.expires_at
      message_parts << "from the #{repo_owner.name} organization and cannot comment"

      if blocked_from_org_content_url
        message_parts << " because of "
        message_parts << link_to("this content", blocked_from_org_content_url)
      end

      # Right now a CoC is returned even if a repo doesn't have one, we check on the url for
      # a truthy value
      if code_of_conduct_url
        message_parts << ". Please read the community's "
        message_parts << link_to("code of conduct", code_of_conduct_url.to_s)
      end

      message_parts << "."
      safe_join(message_parts)
    end
  end
end
