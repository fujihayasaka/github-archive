# typed: true
# frozen_string_literal: true

#
module Newsies
  module Responses
    autoload :Settings, "newsies/responses/settings"
    autoload :Subscription, "newsies/responses/subscription"

    class Boolean < Resiliency::Responses::Boolean
    end

    class Array < Resiliency::Responses::Array
    end

    class Count < Resiliency::Responses::Count
    end

    class Set < Resiliency::Responses::Set
    end

    class WillPaginateCollection < Resiliency::Responses::WillPaginateCollection
    end

    class PageWithPreviousAndNextFlags < Resiliency::Response
      def initialize(&block)
        # Initialize with a plain object as the default return value.
        super(Newsies::PageWithPreviousAndNextFlags.new)
      end
    end
  end
end
