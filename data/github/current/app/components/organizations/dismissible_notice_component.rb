# typed: true
# frozen_string_literal: true

# Renders a User Notice that may be dismissed for a given period.
class Organizations::DismissibleNoticeComponent < ApplicationComponent
  extend T::Sig

  sig { returns(T.any(Symbol, String)) }
  attr_reader :name

  sig { returns Organization }
  attr_reader :org

  sig { returns T::Hash[Symbol, T.untyped] }
  attr_reader :system_arguments

  renders_one :body, lambda { |**system_arguments|
    system_arguments[:tag] = :div
    system_arguments[:w] = :full
    Primer::BaseComponent.new(**system_arguments)
  }

  # Renders a Organization Notice that may be dismissed for a given period. If no duration is provided the notice is
  # dismissed forever on close.
  sig do params(
    name: T.any(Symbol, String),
    user: User, org: Organization,
    # nil duration means the notice is dismissed forever
    duration: T.nilable(ActiveSupport::Duration),
    system_arguments: T.untyped).void
  end
  def initialize(name:, user:, org:, duration: nil, **system_arguments)
    @name = name

    raise ArgumentError, "unregistered organization notice: #{name}" unless User::NoticesDependency::ORGANIZATION_NOTICES.include?(name.to_sym)

    @user = user
    @org = org
    @duration = duration

    @system_arguments = system_arguments
    @system_arguments[:tag] = :div
    @system_arguments[:display] = system_arguments[:display] || :flex
    @system_arguments[:position] = system_arguments[:position] || :relative
    @system_arguments[:data] = (system_arguments[:data] || {}).merge({ "test-selector": "dismissible_notice_#{name}" })
    @system_arguments[:p] = system_arguments[:p] || 3
    @system_arguments[:classes] = class_names(
      "Box",
      "js-notice",
      system_arguments[:classes]
    )
  end

  private

  # Returns when user dismissed the notice
  sig { returns T.nilable(Time) }
  memoize def dismissed_at
    @user.notice_dismissed_at(@name, @org)
  end

  # Returns true if the notice is dismissed. If a dismissed notice is past a given duration,
  # we reset the notice and return false
  sig { returns T::Boolean }
  def is_dismissed_and_maybe_reset?
    return false if dismissed_at.nil?
    return true if @duration.nil?
    did_reset_notice = reset_notice_if_past_duration?
    !did_reset_notice
  end

  sig { returns T::Boolean }
  def reset_notice_if_past_duration?
    return false if dismissed_at.nil? || @duration.nil?
    d = T.must(dismissed_at)
    if Time.now - d > @duration.to_i
      @user.reset_organization_notice(@name, @org)
      true
    else
      false
    end
  end
end
