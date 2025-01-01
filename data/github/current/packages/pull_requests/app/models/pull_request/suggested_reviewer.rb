# typed: true
# frozen_string_literal: true

class PullRequest
  class SuggestedReviewer
    include Comparable

    attr_reader :user, :pull, :author, :commenter, :copilot

    def initialize(user:, pull:, author: 0.0, commenter: 0.0, copilot: 0.0)
      @user = user
      @pull = pull
      @author = author || 0.0
      @commenter = commenter || 0.0
      @copilot = copilot || 0.0
    end

    def author?
      @author > 0
    end

    def commenter?
      @commenter > 0
    end

    def copilot?
      @copilot > 0
    end

    def merge(other)
      self.class.new(
        user: user,
        pull: pull,
        author: @author + other.author,
        commenter: @commenter + other.commenter,
        copilot: @copilot + other.copilot,
      )
    end

    def score
      @author + @commenter + @copilot
    end

    def description
      if copilot?
        "Your AI Pair Programmer"
      elsif author? && commenter?
        "Recently edited and reviewed changes to these files"
      elsif author?
        "Recently edited these files"
      else
        "Recently reviewed these files"
      end
    end

    def <=>(other)
      if other.is_a?(self.class)
        score <=> other.score
      end
    end

    def to_cache
      { user_id: user.id, author: author, commenter: commenter, copilot: copilot }
    end

    def self.from_cache(pull, cache_data)
      user_ids = cache_data.map { |data| data[:user_id] }
      users = User.where(id: user_ids).index_by(&:id)

      cache_data.map do |data|
        user = users[data[:user_id]]
        next unless user

        PullRequest::SuggestedReviewer.new(
          user: user,
          pull: pull,
          author: data[:author],
          commenter: data[:commenter],
          copilot: data[:copilot]
        )
      end.compact
    end

    def self.cache_key(pull, sha = nil)
      sha ||= pull.head_sha
      "pull_request:suggested_reviewers_data:#{pull.id}:#{sha}"
    end
  end
end
