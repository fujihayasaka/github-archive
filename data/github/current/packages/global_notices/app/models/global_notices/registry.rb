# typed: strict
# frozen_string_literal: true

module GlobalNotices
  # Populated at initialization time with the global notices that can be active for users. See the domain interface
  # for usage documentation.

  class Registry
    NO_NOTICE = :no_notice

    class Notice < T::Struct
      const :display_predicate, GlobalNotices::Domain::DisplayPredicate
      const :type, String
      const :snooze_interval, T.nilable(ActiveSupport::Duration)

      sig { params(user: User).returns(T::Boolean) }
      def displays?(user)
        display_predicate.call(user)
      end
    end

    sig { returns(Registry) }
    def self.instance
      @instance ||= T.let(new, T.nilable(Registry))
    end

    sig { void }
    def initialize
      @notices = T.let({}, T::Hash[Symbol, Notice])
    end

    sig do
      params(
        name: Symbol,
        type: String,
        snooze_interval: T.nilable(ActiveSupport::Duration),
        display_predicate: GlobalNotices::Domain::DisplayPredicate
      ).void
    end
    def register(name, type: "warn", snooze_interval: nil, &display_predicate)
      raise ArgumentError, "notice name '#{name}' is already registered" if @notices.key?(name)
      @notices[name] = Notice.new(display_predicate:, type:, snooze_interval:)
    end

    # Returns true if the new name has higher priority than the current named notice.
    # This is purely based on priority and position, without considering the display predicate.
    sig { params(new_name: Symbol, current_name: Symbol).returns(T::Boolean) }
    def supercedes_notice?(new_name:, current_name:)
      return false if new_name == current_name || new_name == NO_NOTICE

      new_notice_priority = @notices.keys.index(new_name) || (raise ArgumentError.new("notice name '#{new_name}' is invalid"))
      return true if current_name == NO_NOTICE

      current_notice_priority = @notices.keys.index(current_name) || (raise ArgumentError.new("notice name '#{current_name}' is invalid"))

      new_notice_priority < current_notice_priority
    end

    # Returns the highest priority notice that applies to the given actor.
    sig { params(user: User).returns(Symbol) }
    def refreshed_notice_name(user)
      @notices.keys.detect { |name| T.must(@notices[name]).displays?(user) } || NO_NOTICE
    end

    sig { params(name: Symbol).returns(T::Boolean) }
    def notice_exists?(name)
      @notices.keys.include?(name)
    end

    sig { params(name: Symbol).returns(Notice) }
    def [](name)
      raise ArgumentError.new("#{name} is not a registered notice") unless @notices.key?(name)
      T.must(@notices[name])
    end
  end
end
