# typed: true
# frozen_string_literal: true

module Codespaces
  class RetentionExpirationComponent < ApplicationComponent

    attr_reader :deletion_time, :size

    def initialize(retention_expires_at:, size: :normal)
      @deletion_time = retention_expires_at
      @size = size
    end

    def time_until_deletion
      return "< 1 hour from now" if deletion_time < 1.hour.from_now
      distance_of_time_in_words(Time.now, deletion_time).sub("about ", "")
    end

    def small?
      size == :small
    end
  end
end
