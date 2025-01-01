# typed: true
# frozen_string_literal: true

module Search
  class DotcomCommitResultView
    include EscapeHelper
    include Commits::CommitMessageable

    attr_reader :oid, :commit, :message, :committer, :author,
                :committed_at, :repository, :highlights, :commit_link
    # Create a new DotcomCommitResultView from a `repository` document hash returned from
    # the dotcom search.
    #
    # hash - Document Hash returned by dotcom search
    #
    def initialize(dotcom_hash)
      @id               = dotcom_hash["id"]
      @oid              = dotcom_hash["sha"]
      @commit           = dotcom_hash["commit"]
      @committer        = dotcom_hash["committer"]
      @author           = dotcom_hash["author"]
      @repository       = DotcomRepoResultView.new(dotcom_hash["repository"])
      @message          = @commit["message"]
      @commit_link      = dotcom_hash["html_url"]

      commit_time    = @commit["committer"]["date"] if @commit["committer"]
      @committed_at  = Time.parse(commit_time)
      @highlights    = Search::DotcomHighlights.highlights(dotcom_hash["text_matches"])
    end

    # Returns true if there are highlight fragments for this commit. The
    # highlight fragments contain text from the various repository fields with the
    # relevant search terms surrounded by <em> tags.
    def highlights?
      !@highlights.nil?
    end

    def committer_avatar
      if committer.present?
        committer["avatar_url"]
      else
        User::AvatarList.default_image_url("gravatar-user-420")
      end
    end

    def author_avatar
      if author.present?
        author["avatar_url"]
      else
        User::AvatarList.default_image_url("gravatar-user-420")
      end
    end

    def committer_link
      committer["html_url"] if committer
    end

    def author_link
      author["html_url"] if author
    end

    def tree_path
      @commit_link.gsub("/commit/", "/tree/")
    end

    def empty_message?
      message.blank?
    end

    # Is the commit author the same as the commit committer? This special cases
    # the "GitHub" committer, which we usually want to ignore in the UI.
    #
    # Returns boolean.
    def committer_is_author?
      return true if committed_via_github?

      if author.nil? || committer.nil?
        commit["committer"]["email"].downcase == commit["author"]["email"].downcase
      else
        author == committer
      end
    end

    # Was this commit made using the GitHub web UI? We determine this by checking
    # the committer name and email.
    #
    # Returns boolean.
    def committed_via_github?
      commit["committer"]["name"] == "GitHub" &&
      commit["committer"]["email"] == GitHub.web_committer_email
    end

    # Return the repo description. The description may or may not contain
    # highlight tags, but either way it has been HTML escaped and is html_safe.
    #
    # Returns an HTML escaped description String.
    def hl_message
      return @hl_message if defined? @hl_message

      @hl_message =
          if highlights? && @highlights.key?("message")
            Commits::CommitMessageHTML.new(@highlights["message"].first, {}, GitHub::Goomba::HighlightedSearchResultPipeline)
          else
            Commits::CommitMessageHTML.new(@message, {})
          end
    end
  end  # RepoResultView
end  # Search
