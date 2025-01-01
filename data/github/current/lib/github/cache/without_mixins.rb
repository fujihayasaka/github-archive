# typed: false
# frozen_string_literal: true

module GitHub
  module Cache
    module WithoutMixins
      # alias all the raw memcache operations we use in GitHub::Cache, so that
      # we can call them without all the GitHub::Cache mixins. These are used
      # by FakeAsync because the mixins all override the behaviour of async_
      # functions directly where this is required, to allow for future alternative
      # implementations that aren't FakeAsync.
      def self.included(klass)
        [:get_multi, :set, :add, :incr, :decr, :delete, :exist?].each do |op|
          klass.class_eval <<-RUBY, __FILE__, __LINE__ + 1
            alias_method :orig_#{op}, :#{op}
          RUBY
        end
      end
    end
  end
end
