# typed: true
# frozen_string_literal: true

module PullRequest::UserReviewedFilesDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { PullRequest }

  # Public: Get a promise that returns the files that the viewer has reviewed for the pull request.
  #
  # Returns a promise.
  def async_viewer_viewed_files(viewer)
    Platform::Loaders::ViewedUserReviewedFiles.load(id, viewer)
  end
end
