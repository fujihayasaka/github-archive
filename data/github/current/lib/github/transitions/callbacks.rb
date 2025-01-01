# typed: false
# frozen_string_literal: true

module GitHub
  module Transitions
    module Callbacks
      def setup_callbacks
        @before_iterate = @after_iterate = lambda { |_user| true }
      end

      def around_iterate(record, method)
        return unless @before_iterate.call(record)
        send method, record
        @after_iterate.call(record)
      end

      # Public: Sets a block to be yielded each record before iteration.  Pass
      # false to skip the record.
      #
      #   mig = NewsiesMigration.new
      #   mig.before_iterate do |user|
      #     user.site_admin?
      #   end
      #
      #   # transitions only staff users
      #   mig.perform
      #
      # Returns nothing.
      def before_iterate(&block)
        @before_iterate = block
      end

      # Public: Sets a block to be yielded each record after iteration.
      #
      #   mig = NewsiesMigration.new
      #   mig.after_iterate do |user|
      #     puts "transitioned #{user}"
      #   end
      #
      #   mig.perform
      #
      # Returns nothing.
      def after_iterate(&block)
        @after_iterate = block
      end
    end
  end
end
