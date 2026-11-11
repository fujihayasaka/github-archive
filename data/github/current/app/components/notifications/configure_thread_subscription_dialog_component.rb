# typed: true
# frozen_string_literal: true

module Notifications
  class ConfigureThreadSubscriptionDialogComponent < ApplicationComponent
    def initialize(list:, thread_class:, thread_id:)
      @list = list
      @thread_class = thread_class
      @thread_id = thread_id
    end

    private

    attr_reader :list, :thread_class, :thread_id
  end
end
