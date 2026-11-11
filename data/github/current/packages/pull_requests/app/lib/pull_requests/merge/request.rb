# typed: strict
# frozen_string_literal: true

module PullRequests
  module Merge
    class Request < T::Struct
      const :mode, Mode
      const :commit_title, T.nilable(String), default: nil
      const :commit_message, T.nilable(String), default: nil
      const :commit_email_address_id, T.nilable(Integer), default: nil
      const :actor_ip_address, T.nilable(String), default: nil
      const :merge_commit_sha, T.nilable(String), default: nil
      const :requested_at, Time
    end
  end
end
