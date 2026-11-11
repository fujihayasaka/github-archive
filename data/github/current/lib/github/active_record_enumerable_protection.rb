# typed: true
# frozen_string_literal: true

# Protection against foot-gun incidents.
#
# ActiveRecord does a lot to transparently provide an Enumerable interface, but
# there are a few places where this can bite you unexpectedly. This module does
# its best to keep you from accidentally shooting yourself in the foot.
module GitHub::ActiveRecordEnumerableProtection
  # Install the protection hooks in ActiveRecord.
  def self.initialize
    ActiveRecord::Relation.module_eval do
      # Protect against User.count { ... }
      prepend CountWithBlockProtection

      prepend UniqProtection
    end

    ActiveRecord::Associations::CollectionProxy.module_eval do
      prepend CollectionProxyInPlaceProtection

      # Protect against User.first.repositories.count { ... }
      prepend CountWithBlockProtection

      prepend UniqProtection
    end
  end

  # Report an error, but don't blow up in production.
  def self.report_error(error)
    if Rails.env.production?
      Failbot.report_trace error
    else
      raise error
    end
  end

  # If you see this error, it's because you're using a method that mutates an
  # array in-place on an ActiveRecord relation. This is dangerous because, while
  # it saves some memory allocation, it can interact poorly with ActiveRecord
  # scopes. For example:
  #
  #   records = SomeModel.scoped
  #   records.select! { |record| record.id.even? }
  #   records.uniq.map(&:id) # => [1, 2, 3, ..]
  #
  # This is because methods like `uniq` are defined on scopes themselves and do
  # not act on the underlying array of loaded records as expected.
  #
  # ActiveRecord::Associations::CollectionProxy behaves in a similar way:
  #
  #   user = User.first
  #   user.emails.map!(&:id)
  #   user.emails.uniq # => NoMethodError: undefined method `id` on Integer:2
  #
  # Consider simply reassigning the results and using a normal filter method:
  #
  #   records = records.select { ... }
  #
  # or use #to_a explicitly:
  #
  #   records = SomeModel.scoped.to_a
  #   records.map! { ... }
  #
  class ARInPlaceModification < StandardError
    def initialize(method)
      super "ActiveRecord collection modified in-place with `#{method}'." +
        "\nUse #to_a explicitly or assign the value to a new variable."
    end
  end

  # If you see this error, it's because you called `count` on a scope and passed
  # in a block. Unfortunately, there's a mismatch between the count method that
  # Enumerable provides and the count method you've called: Enumerable's count
  # takes a block, and ActiveRecord's doesn't. To be explicit: if you call
  # `count` on an AR scope or collection with a block, the block is silently
  # ignored.
  #
  # If you need the block, consider calling #to_a on this scope or association
  # first. For example:
  #
  #   scope   = SomeModel.scoped
  #   ids     = scope.pluck(:id) # => [1, 2, 3, 4]
  #   scope.count      { |record| record.id.even? } # => 4
  #   scope.to_a.count { |record| record.id.even? } # => 2
  #
  class CountWithBlock < StandardError
    def initialize
      super "ActiveRecord count calculation performed with a block, which is ignored." +
        "\nPlease call #to_a first if you need to count using a block."
    end
  end

  # If you see this error, it's because you called `uniq` on a scope.
  # In Rails 5+, AR::Relation#uniq is the same as Enumerable#uniq, to get the
  # previous behaviour use .distinct.
  class UniqOnRelation < StandardError
    def initialize
      super "uniq called on an ActiveRecord scope, which has changed its meaning in Rails 5.2."
      "\nPlease either use #distinct to get a SQL DISTINCT or call #to_a first"
    end
  end

  # If you see this error, it's because you're calling `dup` on a
  # CollectionProxy. In Rails 4.0 `dup` clears out the records rather than
  # saving a copy. This means that when you assign a dup'd CollectionProxy
  # to a variable and then call a method that mutates the CollectionProxy,
  # like `clear` the saved variable will be cleared as well.
  #
  # To avoid, use `to_a` on the CollectionProxy
  #
  # Example:
  #
  #   records = user.followers.dup
  #   user.followers.clear
  #   records.empty? => true
  #
  #   # use to_a instead
  #   records = user.followers.to_a.dup
  #   user.followers.clear
  #   records.empty? => false
  class CollectionProxyDup < StandardError
    def initialize(method)
      super "CollectionProxy's dup does not save the original values in Rails 4+" +

        "\n Use #to_a explictly if you need to save the CollectionProxy before mutating."
    end
  end

  module CollectionProxyInPlaceProtection
    extend T::Helpers
    requires_ancestor { ActiveRecord::Associations::CollectionProxy }

    # Override the dup method in Rails 4 since it doesn't copy the
    # original before mutation
    def dup
      error = CollectionProxyDup.new("dup")
      error.set_backtrace(caller)
      GitHub::ActiveRecordEnumerableProtection.report_error error
      super
    end
  end

  module CountWithBlockProtection
    extend T::Helpers
    requires_ancestor { ActiveRecord::Relation }

    def count(*args, &block)
      if block_given?
        error = CountWithBlock.new
        error.set_backtrace(caller)
        GitHub::ActiveRecordEnumerableProtection.report_error error
      end
      # Using T.unsafe here because of the Splat
      # https://sorbet.org/docs/error-reference#7019
      super(*T.unsafe(args))
    end
  end

  module UniqProtection
    extend T::Helpers
    requires_ancestor { ActiveRecord::Relation }

    def uniq
      error = UniqOnRelation.new
      error.set_backtrace(caller)
      GitHub::ActiveRecordEnumerableProtection.report_error error

      super
    end
  end
end
