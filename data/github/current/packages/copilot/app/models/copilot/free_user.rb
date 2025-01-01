# typed: strict
# frozen_string_literal: true

module Copilot
  class FreeUser < ApplicationRecord::Copilot
    extend Copilot::Helpers

    include Copilot::Helpers
    include Copilot::Metrics

    EXPIRATION_WARNING_DURATION = T.let(3.days, ActiveSupport::Duration)
    MINIMUM_REFRESH_INTERVAL = T.let(30.days, ActiveSupport::Duration)

    class Type < T::Struct
      prop :name, String
      prop :coupon_based, T::Boolean, default: false
      prop :refresh_interval, ActiveSupport::Duration, default: 30.days
    end

    FREE_USER_TYPES = T.let([
      COMPLIMENTARY_ACCESS = T.let(Type.new(
        name: "Complimentary Access",
      ), Type),

     EDUCATIONAL = T.let(Type.new(
        name: "Educational",
        coupon_based: true,
      ), Type),

     ENGAGED_OSS = T.let(Type.new(
        name: "EngagedOSS",
      ), Type),

     FACULTY = T.let(Type.new(
        name: "Faculty",
        coupon_based: true,
      ), Type),

     GITHUB_STAR = T.let(Type.new(
        name: "GitHub Star",
      ), Type),

     HEY_GITHUB = T.let(Type.new(
        name: "Hey GitHub",
      ), Type),

     MS_MVP = T.let(Type.new(
        name: "MS MVP",
        coupon_based: true,
      ), Type),

     TECHNICAL_PREVIEW_EXTENSION = T.let(Type.new(
        name: "Technical Preview Extension",
      ), Type),

      WORKSHOP = T.let(Type.new(
        name: "Workshop",
        coupon_based: true,
      ), Type),

     Y_COMBINATOR = T.let(Type.new(
        name: "Y Combinator",
      ), Type),
    ].freeze, T::Array[Type])

    self.table_name = "copilot_complimentary_users"
    self.strict_loading_by_default = true

    alias_attribute :next_check_at, :last_checked_date

    belongs_to :user, class_name: "::User", strict_loading: false

    validates :user, presence: true
    validates :free_user_type, inclusion: { in: FREE_USER_TYPES.map(&:name), message: "must be a valid free user type" }

    FREE_USER_TYPES.each do |free_user_type|
      scope free_user_type.name.parameterize, -> {
        where(free_user_type: free_user_type.name)
      }
    end

    scope :not_subscribed, -> {
      where(
        free_user_type: [
          EDUCATIONAL.name,
          ENGAGED_OSS.name,
          FACULTY.name,
          GITHUB_STAR.name,
          MS_MVP.name,
          WORKSHOP.name,
        ],
        subscribed: false,
        subscribed_at: nil,
      ).where("created_at < ?", 2.days.ago)
    }

    scope :needs_updating, -> {
      where(
        subscribed: true,
      ).where("last_checked_date <= ?", Date.current)
    }

    sig { params(name: String).returns(Type) }
    def self.type(name)
      FREE_USER_TYPES.find { |type| type.name == name } ||
        raise(ArgumentError, "Invalid free user type: #{name.inspect}")
    end

    sig { params(copilot_user: Copilot::User).returns(T.nilable(Copilot::FreeUser)) }
    def self.find_for_copilot_user(copilot_user)
      copilot_user.collect_metrics("copilot.free_user.find_for_copilot_user") do
        return nil if copilot_user.free_user_blocked?
        # first let's see if we have a free user record for this user
        free_user = find_by(user_id: copilot_user.id)

        # if we do, let's just return it, mmkay?
        if free_user.present?
          GitHub.dogstats.increment("copilot.free_user.find_for_copilot_user.exists")
          return free_user
        end

        GitHub.dogstats.increment("copilot.free_user.find_for_copilot_user.notfound")

        if is_github_star_user?(copilot_user)
          GitHub.dogstats.increment "copilot.free_user.github_star_user"

          self.find_or_create_free_user!(
            user_id: copilot_user.id,
            free_user_type: GITHUB_STAR.name,
            last_checked_date: 1.year.from_now.to_date,
          )
        elsif is_educational_user?(copilot_user) || is_faculty_user?(copilot_user) || is_ms_mvp_user?(copilot_user) || is_workshop_user?(copilot_user)
          coupon_redemption = T.must(copilot_user.user_object.coupon_redemption)
          coupon = T.must(coupon_redemption.coupon)

          GitHub.dogstats.increment("copilot.free_user.coupon_user", tags: ["coupon_code:#{coupon_redemption_type(coupon.code).name}"])

          self.find_or_create_free_user!(
            user_id: copilot_user.id,
            free_user_type: coupon_redemption_type(coupon.code).name,
            last_checked_date: [coupon_redemption.expires_at.to_date, 30.days.from_now.to_date].max,
          )
        elsif is_engaged_oss_user?(copilot_user)
          GitHub.dogstats.increment("copilot.free_user.engaged_oss_user")
          self.find_or_create_free_user!(
            user_id: copilot_user.id,
            free_user_type: ENGAGED_OSS.name,
            last_checked_date: 1.year.from_now.to_date,
          )
        else
          # this will end up returning nil back to the user check which is cool cause we'll check for that
          nil
        end
      end
    end

    # Creates a FreeUser for the given user_id if one doesn't already exist.
    # This method is resilient to race conditions causing duplicate key errors
    # on the unique index for user_id; in that case it returns the existing row.
    sig do
      params(
        user_id: Integer,
        free_user_type: String,
        last_checked_date: Date,
      ).returns(Copilot::FreeUser)
    end
    def self.find_or_create_free_user!(user_id:, free_user_type:, last_checked_date:)
      free_user = FreeUser.find_by(user_id: user_id)

      if free_user.present?
        GitHub.dogstats.increment("copilot.free_user.find_or_create_free_user.exists")
        return free_user
      end

      begin
        free_user = with_write { FreeUser.create!(user_id: user_id, free_user_type: free_user_type, last_checked_date: last_checked_date) }
        GitHub.dogstats.increment("copilot.free_user.find_or_create_free_user.created", tags: ["free_user_type:#{free_user.free_user_type}"])
        free_user
      rescue ActiveRecord::RecordNotUnique
        GitHub.dogstats.increment("copilot.free_user.find_or_create_free_user.duplicate_ar")
        T.must(FreeUser.find_by(user_id: user_id))
      rescue StandardError => e
        # detect duplicate key
        if e.message.include?("Duplicate entry")
          GitHub.dogstats.increment("copilot.free_user.find_or_create_free_user.duplicate_trilogy")
          T.must(FreeUser.find_by(user_id: user_id))
        else
          raise
        end
      end
    end

    private_class_method :find_or_create_free_user!

    sig { params(code: String).returns(Type) }
    def self.coupon_redemption_type(code)
      return MS_MVP if code.start_with?("MVP-")
      return FACULTY if code.start_with?("faculty")
      return WORKSHOP if code.start_with?("cfp-")
      EDUCATIONAL
    end

    sig { params(copilot_user: Copilot::User).returns(T::Boolean) }
    def self.is_educational_user?(copilot_user)
      copilot_user.collect_metrics("copilot.free_user.is_educational_user") do
        with_read do
          educational_coupon_redemption(copilot_user).present?
        end
      end
    end

    sig { params(copilot_user: Copilot::User).returns(T::Boolean) }
    def self.is_engaged_oss_user?(copilot_user)
      copilot_user.collect_metrics("copilot.free_user.is_engaged_oss_user") do
        with_read do
          Copilot::EngagedOssUser.where(user_id: copilot_user.id).exists?
        end
      end
    end

    sig { params(copilot_user: Copilot::User).returns(T::Boolean) }
    def self.is_faculty_user?(copilot_user)
      copilot_user.collect_metrics("copilot.free_user.is_faculty_user") do
        with_read do
          faculty_coupon_redemption(copilot_user).present?
        end
      end
    end

    sig { params(copilot_user: Copilot::User).returns(T::Boolean) }
    def self.is_github_star_user?(copilot_user)
      copilot_user.collect_metrics("copilot.free_user.is_github_star_user") do
        with_read do
          copilot_user.user_object.github_star?
        end
      end
    end

    sig { params(copilot_user: Copilot::User).returns(T::Boolean) }
    def self.is_ms_mvp_user?(copilot_user)
      copilot_user.collect_metrics("copilot.free_user.is_ms_mvp_user") do
        with_read do
          copilot_user.user_object.microsoft_mvp?
        end
      end
    end

    sig { params(copilot_user: Copilot::User).returns(T::Boolean) }
    def self.is_workshop_user?(copilot_user)
      copilot_user.collect_metrics("copilot.free_user.is_workshop_user") do
        with_read do
          workshop_coupon_redemption(copilot_user).present?
        end
      end
    end

    sig { params(copilot_user: Copilot::User).returns(T.nilable(CouponRedemption)) }
    def self.educational_coupon_redemption(copilot_user)
      return nil unless copilot_user.user_object.coupon_redemption.present?

      educational_coupon_codes = ["student-partner"] + [DateTime.now.year, DateTime.now.year - 1, DateTime.now.year - 2].map do |year|
        "students-#{year}"
      end

      copilot_user.user_object.coupon_redemption if educational_coupon_codes.include?(copilot_user.user_object.coupon_redemption&.coupon&.code)
    end

    sig { params(copilot_user: Copilot::User).returns(T.nilable(CouponRedemption)) }
    def self.faculty_coupon_redemption(copilot_user)
      return nil unless copilot_user.user_object.coupon_redemption.present?

      copilot_user.user_object.coupon_redemption if copilot_user.user_object.coupon&.code.to_s.start_with?("faculty")
    end

    sig { params(copilot_user: Copilot::User).returns(T.nilable(CouponRedemption)) }
    def self.workshop_coupon_redemption(copilot_user)
      return nil unless copilot_user.user_object.coupon_redemption.present?

      copilot_user.user_object.coupon_redemption if copilot_user.user_object.coupon&.code.to_s.start_with?("cfp")
    end

    sig { returns(String) }
    def to_s
      "id: #{id}, user_id: #{user_id}, free_user_type: #{free_user_type}, subscribed: #{subscribed}, subscribed_at: #{subscribed_at}, last_checked_date: #{last_checked_date}, next_check_at: #{next_check_at}"
    end

    sig { returns(T::Hash[String, String]) }
    def to_otel
      {
        "gh.copilot.free_user.id" => id,
        "gh.user.id" => user_id,
        "gh.copilot.free_user.free_user_type" => free_user_type,
        "gh.copilot.free_user.subscribed" => subscribed.to_s,
        "gh.copilot.free_user.subscribed_at" => subscribed_at.to_s,
        "gh.copilot.free_user.last_checked_date" => last_checked_date.to_s,
        "gh.copilot.free_user.next_check_at" => next_check_at.to_s,
      }
    end

    sig { returns(Type) }
    def type
      self.class.type(free_user_type)
    end

    sig { returns(T::Class[T.anything]) }
    def sorbet_class
      self.class
    end

    sig { returns(T::Boolean) }
    def should_update?
      value = !!(next_check_at <= Date.current && subscribed?)
      GitHub.dogstats.increment("copilot.free_user.should_update", tags: ["value:#{value}"])
      value
    end

    sig { returns(T::Boolean) }
    def subscribe
      collect_metrics("copilot.free_user.subscribe") do
        update(subscribed: true, subscribed_at: Time.now)
        true
      end
    end

    # Warns the free user that their access is about to expire. A background
    # job is then scheduled to delete the user after 3 days via #expire!.
    sig { void }
    def warn_and_queue_cancel!
      GitHub.logger.with_named_tags(otel_tags("warn_and_queue_cancel!")) do
        GitHub.logger.info "Warning free user"

        # if the user doesn't exist, we can't do anything
        return if cleanup?

        with_write do
          update!(
            last_checked_date: Date.today + T.cast(EXPIRATION_WARNING_DURATION, Integer) + 1.day
          )
        end

        Copilot::FreeUserCancellationJob
          .set(wait: EXPIRATION_WARNING_DURATION)
          .perform_later(id)

        if FeatureFlag.vexi.enabled_or_raise?(:copilot_free_user_warn_email, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
          CopilotFreeUserMailer
            .expiration_warning(T.must(user), EXPIRATION_WARNING_DURATION.from_now)
            .deliver_later
        end

        Copilot::Instrumenter.instrument_free_user_warned(Copilot::User.new(T.must(user)))
        GitHub.dogstats.increment("copilot.free_user.user_warned", tags: ["free_user_type:#{free_user_type}"])
      end
    end

    # Deletes the free user and sends an email to the user.
    sig { void }
    def cancel!
      GitHub.logger.with_named_tags(otel_tags("cancel!")) do
        GitHub.logger.info "Cancelling free user"

        return if cleanup?

        with_write do
          destroy!
        end

        if FeatureFlag.vexi.enabled_or_raise?(:copilot_free_user_expired_email, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
          CopilotFreeUserMailer.expired(T.must(user)).deliver_later
        end

        Copilot::Instrumenter.instrument_free_user_cancelled(Copilot::User.new(T.must(user)))
        GitHub.dogstats.increment("copilot.free_user.user_cancelled", tags: ["free_user_type:#{free_user_type}"])
      end
    end

    # This method takes a free user and refreshes it and instruments/etc.
    sig { void }
    def refresh!
      GitHub.logger.with_named_tags(otel_tags("refresh!")) do
        GitHub.logger.info "Refreshing free user"

        return if cleanup?

        dotcom_user = T.must(user)
        next_check_at = MINIMUM_REFRESH_INTERVAL.from_now
        coupon_expires_at = nil

        if type.coupon_based
          coupon_redemption = dotcom_user.coupon_redemption

          if !coupon_redemption
            GitHub.logger.info "Coupon redemption missing"
            GitHub.dogstats.increment "copilot.free_user.refresh.coupon_redemption_missing",
              tags: ["free_user_type:#{free_user_type}"]

            cancel!
            return
          end

          if coupon_redemption.stale?
            GitHub.logger.info "Coupon redemption stale",
              "gh.coupon_redemption.id": coupon_redemption.id,
              "gh.coupon_redemption.expires_at": coupon_redemption.expires_at

            GitHub.dogstats.increment "copilot.free_user.refresh.coupon_redemption_stale",
              tags: ["free_user_type:#{free_user_type}"]

            cancel!
            return
          end

          # Coupon-based users are refreshed when their coupon is set to
          # expire.
          coupon_expires_at = coupon_redemption.expires_at.utc.to_date
          next_check_at = coupon_expires_at + 1.day
        else
          # Non-coupon based users are refreshed every 30 days.
          next_check_at = [
            type.refresh_interval.from_now,
            MINIMUM_REFRESH_INTERVAL.from_now,
          ].max
        end

        with_write do
          GitHub.logger.info "Updating next_check_at",
            "gh.coupon_redemption.id": coupon_redemption&.id,
            "gh.coupon_redemption.expires_at": coupon_redemption&.expires_at,
            "gh.copilot.free_user.last_checked_date": next_check_at
          update!(next_check_at: next_check_at)
        end

        if FeatureFlag.vexi.enabled_or_raise?(:copilot_free_user_refresh_email, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
          CopilotFreeUserMailer.refreshed(
            dotcom_user,
            next_check_at.to_date,
            coupon_expires_at
          ).deliver_later
        end

        copilot_user = Copilot::User.new(dotcom_user)
        Copilot::Instrumenter.instrument_free_user_refreshed(copilot_user)

        GitHub.dogstats.increment "copilot.free_user.user_refreshed",
          tags: ["free_user_type:#{free_user_type}"]
      end
    end

    # this will clean up the the free user if the user associated has been deleted
    sig { returns(T::Boolean) }
    def cleanup?
      # if the user is present, we don't do anything
      return false if user.present?

      GitHub.dogstats.increment("copilot.free_user.cleanup")
      # if the user is not present, we destroy ourselves and return the outcome
      destroy
    end

    sig { returns(T::Hash[Symbol, T.any(T::Boolean, String)]) }
    def tags
      Hash.new.tap do |tags|
        site_admin = user.present? ? T.must(user).site_admin? : false
        tags[:free_user_type]    = free_user_type
        tags[:is_staff]          = T.cast(site_admin, T::Boolean)
        tags[:last_checked_date] = last_checked_date.to_s
        tags[:next_check_at]     = next_check_at.to_s
        tags[:subscribed]        = subscribed.to_s
      end
    end

    sig { params(function: String).returns(T::Hash[String, T.any(T::Boolean, String)]) }
    def otel_tags(function)
      {
        "code.function": function,
        "gh.copilot.free_user.free_user_type": free_user_type,
        "gh.copilot.free_user.last_checked_date": last_checked_date,
        "gh.copilot.free_user.subscribed": subscribed,
        "gh.copilot.free_user.subscribed_at": subscribed_at,
        "gh.user.id": user_id,
      }
    end

    sig { returns(T.nilable(Integer)) }
    def to_i
      id
    end

    sig { params(copilot_user: Copilot::User).returns(T::Array[Type]) }
    def self.eligible_types_for(copilot_user)
      FREE_USER_TYPES.select do |type|
        case type.name
        when GITHUB_STAR.name
          is_github_star_user?(copilot_user)
        when EDUCATIONAL.name
          is_educational_user?(copilot_user)
        when ENGAGED_OSS.name
          is_engaged_oss_user?(copilot_user)
        when FACULTY.name
          is_faculty_user?(copilot_user)
        when MS_MVP.name
          is_ms_mvp_user?(copilot_user)
        when WORKSHOP.name
          is_workshop_user?(copilot_user)
        else
          # Default: allow all other types (e.g., Complimentary Access, Hey GitHub, Technical Preview Extension, Y Combinator)
          true
        end
      end
    end
  end
end
