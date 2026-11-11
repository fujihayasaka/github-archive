# typed: strict
# frozen_string_literal: true

module GlobalNotices
  class Domain < GH::Domain::Base
    # Block used to determine if the given notice should be displayed.
    DisplayPredicate = T.type_alias { T.proc.params(viewer: User).returns(T::Boolean) }

    # Returns the current global notice for the given user id.
    sig { params(user: User).returns(IGlobalNotice) }
    def current_notice(user)

      # TODO: Using the relation to avoid extra queries on the web layout at this stage.
      # We can migrate to a user_id or even GH.identity_context.actor.id later.
      notice = user.global_notice

      # The notice may be old and no longer applicable. If so, treat it the same as no notice.
      unless Registry.instance.notice_exists?(notice.name.to_sym) || notice.name == Registry::NO_NOTICE
        notice.name = Registry::NO_NOTICE
      end

      notice
    end

    # Register a notice with the given name. If a notice with the same name is already registered,
    # an ArgumentError is raised.
    #
    # name              - The Symbol name of the notice. This is used to identify the notice and should be unique.
    # type              - The String type of the notice. This is used to determine the visual style of the notice.
    # snooze_interval   - The duration until the notice can be snoozed again. If nil, the notice cannot be snoozed.
    # display_predicate - A block that is called to determine if the notice is applicable to the given user. The
    #                     block is called with the user as the only argument and should return a boolean value. If
    #                     the block returns true, the notice is considered applicable to the user. If the block
    #                     returns false, the notice is not applicable.
    sig do
      params(
        name: Symbol,
        type: String,
        snooze_interval: T.nilable(ActiveSupport::Duration),
        display_predicate: GlobalNotices::Domain::DisplayPredicate
      ).void
    end
    def register(name, type: "warn", snooze_interval: nil, &display_predicate)
      Registry.instance.register(name, type:, snooze_interval:, &display_predicate)
    end

    # Set the current global notice name for the given user to the given name.
    # * If the current notice for the user is higher priority, nothing is changed.
    #
    # Returns the symbol of the currently persisted notice, new or existing.
    sig { params(user: User, name: Symbol).returns(IGlobalNotice) }
    def set(user:, name:)
      notice_record = T.let(user.global_notice, GlobalNotice)
      notice_record.set(name)
      notice_record
    end

    # Snooze the global notice for the given user, if the notice can be snoozed.
    #
    # Returns
    #   - GH::Result::Ok on success.
    #   - GH::Result::Error::NotFound if the notice is not found or its name does not match the given name.
    #   - GH::Result::Error::Argument if the notice cannot be snoozed.
    sig { params(user: User, name: Symbol).returns(GH::Result[T::Boolean]) }
    def snooze(user:, name:)
      notice = GlobalNotice.find_by(user_id: user.id)
      return GH::Result::Error::NotFound.new unless notice.present?
      return GH::Result::Error::NotFound.new if notice.name.to_sym != name

      interval = notice.snooze_interval
      return GH::Result::Error::Argument.new("This notice type cannot be snoozed.") if interval.nil?

      user.dismiss_notice(notice.name.to_sym, expires: interval.from_now, kv_store: GitHub::Authentication::KV.store)
      GH::Result::Ok.new(true)
    end

    # Queue a background job to refresh the global notice for the given user.
    # Refreshing the global notice can be a costly operation and should not be done synchronously.
    sig { params(user_id: Integer).void }
    def refresh(user_id)
      GlobalNoticeNextRefreshJob.set(wait: 5.minutes).perform_later(user_id)
    end
  end
end
