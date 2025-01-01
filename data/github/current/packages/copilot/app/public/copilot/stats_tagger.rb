# typed: strict
# frozen_string_literal: true

module Copilot
  class StatsTagger

    sig { returns(T.nilable(T.any(Copilot::Business, Copilot::FreeUser, Copilot::LimitedUser, Copilot::Organization, Copilot::User))) }
    attr_reader :copilot_object

    sig { params(copilot_object: Objectable, tags: T::Hash[Symbol, String]).void }
    def initialize(copilot_object: nil, **tags)
      @tags           = T.let(tags.with_indifferent_access, T::Hash[Symbol, String])
      @copilot_object = T.let(load_copilot_object(copilot_object), T.nilable(T.any(Copilot::Business, Copilot::FreeUser, Copilot::LimitedUser, Copilot::Organization, Copilot::User)))
      load_tags
    end

    sig { returns(T::Hash[Symbol, String]) }
    def all_tags
      @tags
    end

    sig { void }
    def load_tags
      add_user_tags
      add_limited_user_tags
      add_free_user_tags
      add_business_tags
      add_organization_tags

      @tags.compact!
    end

    sig { returns(T::Array[String]) }
    def datadog_tags
      []
    end

    private

    sig do
      params(copilot_object: Objectable).returns(
         T.nilable(
           T.any(
             Copilot::Business,
             Copilot::FreeUser,
             Copilot::LimitedUser,
             Copilot::Organization,
             Copilot::User,
           )
         )
       )
    end
    def load_copilot_object(copilot_object)
      case copilot_object
      when ::Business
        Copilot::Business.new(copilot_object)
      when ::Organization
        Copilot::Organization.new(copilot_object)
      when ::User
        Copilot::User.new(copilot_object)
      else
        copilot_object
      end
    end

    sig { void }
    def add_user_tags
      return unless @copilot_object && @copilot_object.sorbet_class == ::User

      obj = T.cast(@copilot_object, Copilot::User)
      site_admin = obj.user_object.site_admin?

      @tags.reverse_merge!(
        user_id: obj.user_object.id,
        user_login: obj.user_object.display_login,
        free_user_type: nil, #default value
        is_staff: site_admin,
      )
    rescue StandardError => e # rubocop:todo Lint/RescueException
      Copilot::ErrorReporter.report!(e, copilot_user: obj)
    end

    sig { void }
    def add_free_user_tags
      return unless @copilot_object && @copilot_object.sorbet_class == Copilot::FreeUser

      obj = T.cast(@copilot_object, Copilot::FreeUser)
      site_admin = false

      if obj.user.present?
        site_admin = T.must(obj.user).site_admin?
      end

      @tags.reverse_merge!(
        user_id: obj.user&.id,
        user_login: obj.user&.display_login,
        free_user_type: obj.free_user_type,
        last_checked_date: obj.last_checked_date.to_s,
        next_check_at: obj.next_check_at.to_s,
        subscribed: obj.subscribed.to_s,
        is_staff: site_admin,
      )
    rescue StandardError => e # rubocop:todo Lint/RescueException
      Copilot::ErrorReporter.report!(Copilot::Errors::StatsError.from_error(e),
        copilot_user: obj&.user
      )
    end

    sig { void }
    def add_limited_user_tags
      return unless @copilot_object && @copilot_object.sorbet_class == Copilot::LimitedUser

      obj = T.cast(@copilot_object, Copilot::LimitedUser)
      site_admin = false

      if obj.user.present?
        site_admin = T.must(obj.user).site_admin?
      end

      @tags.reverse_merge!(
        user_id: obj.user&.id,
        user_login: obj.user&.display_login,
        subscribed: obj.subscribed?.to_s,
        is_staff: site_admin,
      )
    rescue StandardError => e # rubocop:todo Lint/RescueException
      Copilot::ErrorReporter.report!(Copilot::Errors::StatsError.from_error(e),
        copilot_user: obj&.user
      )
    end

    sig { void }
    def add_business_tags
      return unless @copilot_object && @copilot_object.sorbet_class == ::Business

      obj = T.cast(@copilot_object, Copilot::Business)
      @tags.reverse_merge!(
        business_id: obj.business_object.id,
        business_slug: obj.business_object.slug,
        business_enablement_setting: obj.copilot_business_enablement_setting,
      )
    rescue StandardError => e # rubocop:todo Lint/RescueException
      Copilot::ErrorReporter.report!(Copilot::Errors::StatsError.from_error(e), copilot_business: obj)
    end

    sig { void }
    def add_organization_tags
      return unless @copilot_object && @copilot_object.sorbet_class == Copilot::Organization
      obj = T.cast(@copilot_object, Copilot::Organization)

      @tags.reverse_merge!(
        organization_id: obj.organization_object.id,
        organization_login: obj.organization_object.display_login,
        copilot_enabled_setting: obj.copilot_enabled_setting.to_s,
        copilot_snippy_setting: obj.copilot_snippy_setting.to_s,
        seat_management_setting: obj.seat_management_setting.to_s,
      )
    rescue StandardError => e # rubocop:todo Lint/RescueException
      Copilot::ErrorReporter.report!(Copilot::Errors::StatsError.from_error(e), copilot_organization: obj)
    end
  end
end
