# typed: true
# frozen_string_literal: true

module PullRequests
  class ActionsPromptComponent < ApplicationComponent
    attr_reader :pull_request, :repo, :task, :user, :actions

    def initialize(user:, pull_request:)
      @user = user
      @pull_request = pull_request
      @repo = pull_request.repository
      @task = ActionsPrompt::FlamingoActionsTask.new(@pull_request)
      @actions = ActionsPrompt::FlamingoActions.new(@repo)
    end

    def render?
      return false unless repo.writable_by?(user)

      allowed_task? && actions.allowed_experience?
    end

    memoize def allowed_task?
      !user.dismissed_notice?(notice_key) && !task.completed? && task.repo_candidate?
    end

    def notice_key
      task.class.const_get(:NOTICE_KEY)
    end
  end
end
