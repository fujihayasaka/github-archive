# typed: strict
# frozen_string_literal: true

module PullRequests
  # PR settings for a given user and repository.
  #
  # A `nil` user represents a logged out user: in this situation getters return
  # default values, and setters do nothing.
  class UserSettings
    extend T::Sig

    sig { params(user: T.nilable(Users::IUser), repository: Repositories::IRepository).void }
    def initialize(user, repository)
      @user = user
      @repository = repository
    end

    sig { returns(T::Boolean) }
    def default_pull_requests_to_draft?
      return false if @user.nil?

      default_to_draft_kv.get(default_pull_requests_to_draft_key(@user)).value { "false" } == "true"
    rescue => exception # rubocop:disable Lint/GenericRescue
      Failbot.report exception
      false
    end

    sig { params(value: T::Boolean).void }
    def set_default_pull_requests_to_draft(value)
      return if @user.nil?

      if value
        key = default_pull_requests_to_draft_key(@user)
        default_to_draft_kv.set(key, "true", expires: 1.month.from_now)
      else
        clear_default_pull_requests_to_draft
      end
    rescue => exception # rubocop:disable Lint/GenericRescue
      Failbot.report exception
    end

    sig { void }
    def clear_default_pull_requests_to_draft
      return if @user.nil?

      key = default_pull_requests_to_draft_key(@user)
      default_to_draft_kv.del(key)
    end

    private

    sig { returns(GitHub::KV) }
    def default_to_draft_kv
      PullRequests::KV.for_repository(@repository)
    end

    sig { params(user: Users::IUser).returns(String) }
    def default_pull_requests_to_draft_key(user)
      "pull_requests/default_to_draft/user#{user.id}"
    end
  end
end
