# typed: true
# frozen_string_literal: true

module Diff
  class FileReviewView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    extend UrlHelper

    attr_reader :pull_request
    attr_reader :path
    attr_reader :user
    attr_reader :reviewed
    attr_reader :user_reviewed_files

    def after_initialize
      @user_reviewed_files ||= PullRequestUserReviews.new(pull_request, user)
    end

    def reviewed?
      if reviewed.nil?
        user_reviewed_files&.reviewed?(path)
      else
        reviewed
      end
    end

    def dismissed?
      user_reviewed_files&.dismissed?(path)
    end
  end
end
