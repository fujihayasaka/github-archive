# typed: true
# frozen_string_literal: true

class Api::App
  class AdvisoryWorkspaceAllowlist
    ROUTE_ALLOW_LIST = {
      '\/repositories\/(\d+)\/readme(?:\/(.*))?' => %w(GET),
      '\/repositories\/(\d+)\/contents\/(.+)' => %w(DELETE PUT),
      '\/repositories\/(\d+)\/tarball(?:\/(.*))?' => %w(GET),
      '\/repositories\/(\d+)\/zipball(?:\/(.*))?' => %w(GET),
      "/repositories/:repository_id" => %w(DELETE GET),
      "/repositories/:repository_id/branches" => %w(GET),
      "/repositories/:repository_id/branches/*" => %w(GET),
      "/repositories/:repository_id/comments" => %w(GET POST),
      "/repositories/:repository_id/comments/:comment_id" => %w(DELETE GET PATCH POST),
      "/repositories/:repository_id/comments/:comment_id/reactions" => %w(GET POST),
      "/repositories/:repository_id/commits" => %w(GET),
      "/repositories/:repository_id/commits/*" => %w(GET),
      "/repositories/:repository_id/commits/*/comments" => %w(GET POST),
      "/repositories/:repository_id/compare/*" => %w(GET),
      "/repositories/:repository_id/contents(/*)?" => %w(GET),
      "/repositories/:repository_id/contributors" => %w(GET),
      "/repositories/:repository_id/events" => %w(GET),
      "/repositories/:repository_id/git" => %w(GET),
      "/repositories/:repository_id/git/blobs/:sha" => %w(GET),
      "/repositories/:repository_id/git/blobs" => %w(POST),
      "/repositories/:repository_id/git/commits" => %w(POST),
      "/repositories/:repository_id/git/commits/:commit_id" => %w(GET),
      "/repositories/:repository_id/git/refs" => %w(GET POST),
      "/repositories/:repository_id/git/refs/*" => %w(DELETE GET PATCH),
      "/repositories/:repository_id/git/tags" => %w(POST),
      "/repositories/:repository_id/git/tags/:tag_id" => %w(GET),
      "/repositories/:repository_id/languages" => %w(GET),
      "/repositories/:repository_id/license" => %w(GET),
      "/repositories/:repository_id/pulls" => %w(GET POST),
      "/repositories/:repository_id/pulls/:pull_number" => %w(GET PATCH),
      "/repositories/:repository_id/pulls/:pull_number/comments" => %w(GET POST),
      "/repositories/:repository_id/pulls/:pull_number/commits" => %w(GET),
      "/repositories/:repository_id/pulls/:pull_number/files" => %w(GET),
      "/repositories/:repository_id/pulls/:pull_number/merge" => %w(GET),
      "/repositories/:repository_id/pulls/:pull_number/requested_reviewers" => %w(DELETE GET POST),
      "/repositories/:repository_id/pulls/:pull_number/reviews" => %w(GET POST),
      "/repositories/:repository_id/pulls/:pull_number/reviews/:review_id" => %w(DELETE GET PUT),
      "/repositories/:repository_id/pulls/:pull_number/reviews/:review_id/comments" => %w(GET),
      "/repositories/:repository_id/pulls/:pull_number/reviews/:review_id/dismissals" => %w(PUT),
      "/repositories/:repository_id/pulls/:pull_number/reviews/:review_id/events" => %w(POST),
      "/repositories/:repository_id/pulls/comments" => %w(GET),
      "/repositories/:repository_id/pulls/comments/:comment_id" => %w(DELETE GET PATCH),
      "/repositories/:repository_id/pulls/comments/:comment_id/reactions" => %w(GET POST),
      "/repositories/:repository_id/git/trees" => %w(POST),
      "/repositories/:repository_id/git/trees/*" => %w(GET),
      "/repositories/:repository_id/notifications" => %w(GET PUT),
      "/repositories/:repository_id/releases" => %w(GET POST),
      "/repositories/:repository_id/releases/:release_id" => %w(DELETE GET PATCH),
      "/repositories/:repository_id/releases/:release_id/assets" => %w(GET),
      "/repositories/:repository_id/releases/assets/:asset_id" => %w(DELETE GET PATCH),
      "/repositories/:repository_id/releases/latest" => %w(GET),
      "/repositories/:repository_id/releases/tags/*" => %w(GET),
      "/repositories/:repository_id/subscribers" => %w(GET),
      "/repositories/:repository_id/subscription" => %w(GET PUT),
      "/repositories/:repository_id/tags" => %w(GET),
      "/repositories/:repository_id/watchers" => %w(GET),
    }.freeze

    def self.allowed?(repo, route, method)
      allowed_methods = ROUTE_ALLOW_LIST[route]
      allowed_methods&.include?(method)
    end
  end
end
