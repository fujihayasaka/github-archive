# frozen_string_literal: true

# I don't condone or approve of my actions in adding methods to a core Ruby type.
# I've tried to make this somewhat more responsible by checking that the method
# doesn't already exist, don't hate me.
# The name drop_after is taken from https://bugs.ruby-lang.org/issues/18136#note-8
# which requests this functionality.
unless Enumerator.method_defined?(:drop_after)
  class Enumerator
    def drop_after
      Enumerator.new do |y|
        loop do
          value = self.next
          y << value
          break if yield(value)
        end
      end
    end

    class Lazy
      def drop_after
        Enumerator.new do |y|
          loop do
            value = self.next
            y << value
            break if yield(value)
          end
        end.lazy
      end
    end
  end
end
