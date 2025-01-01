# typed: true
# frozen_string_literal: true

class UserLists::FeedbackComponent < ApplicationComponent
  FEEDBACK_REPO_DISCUSSIONS_PATH = "/github/feedback/discussions"

  # system_arguments - Hash of keyword arguments. Applied to the outermost <div> as Primer system arguments. See
  #  https://primer.style/view-components/system-arguments.
  def initialize(**system_arguments)
    @system_arguments = system_arguments
  end

  private

  attr_reader :system_arguments

  def feedback_url
    "https://github.com/#{FEEDBACK_REPO_DISCUSSIONS_PATH}/categories/lists"
  end
end
