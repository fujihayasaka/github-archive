# typed: true
# frozen_string_literal: true

module PullRequests
  class BodyComponent < ApplicationComponent
    include AvatarHelper
    include UrlHelper

    attr_reader :pull_request

    def initialize(pull_request:)
      @pull_request = pull_request
    end

    private

    def action_menu_path
      actions_menu_path(
        href: dom_id,
        user_id: pull_request.repository.owner_display_login,
        repository: pull_request.repository.name,
        id: pull_request.number,
        gid: pull_request.global_relay_id,
      )
    end

    def action_text
      "commented"
    end

    def form_path
      "/#{pull_request.repository.name_with_display_owner}/issues/#{pull_request.number}"
    end

    def dom_id
      "issue-#{pull_request.issue.id}"
    end

    def body_html
      pull_request.body_html(context: pull_request.body_html_context(viewer: current_user, cap_filter:)) || GitHub::HTMLSafeString::EMPTY
    end

    memoize def author
      pull_request.async_user.then do |user|
        next User.ghost if user.nil? || user.hide_from_user?(current_user)
        user
      end.sync
    end

    def data_url
      pull_request_body_partial_path
    end

    def websocket_channel
      GitHub::WebSocket::Channels.pull_request(pull_request)
    end
  end
end
