# typed: strict
# frozen_string_literal: true

module GlobalNotices
  module IGlobalNotice
    extend T::Helpers

    abstract!

    sig { abstract.returns(String) }
    def name; end

    sig { returns(String) }
    def type
      GlobalNotices::Registry.instance[name.to_sym].type
    end

    sig { returns(T.nilable(ActiveSupport::Duration)) }
    def snooze_interval
      GlobalNotices::Registry.instance[name.to_sym].snooze_interval
    end

    sig { params(user: User).returns(T::Boolean) }
    def display?(user)
      GlobalNotices::Registry.instance[name.to_sym].displays?(user)
    end
  end
end
