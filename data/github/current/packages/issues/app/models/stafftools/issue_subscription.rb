# typed: true
# frozen_string_literal: true

module Stafftools
  class IssueSubscription
    include NewsiesReasons

    attr_reader :reason
    attr_reader :user

    def initialize(user, reason)
      @user = user
      @reason = reason
    end
  end
end
