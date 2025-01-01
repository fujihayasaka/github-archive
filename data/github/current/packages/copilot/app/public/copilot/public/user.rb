# typed: strict
# frozen_string_literal: true

module Copilot
  module Public
    class User
      extend T::Sig
      include T::Helpers
      include GitHub::Memoizer

      # About versioning:
      # CURRENT_VERSION is the version of the cache that is being written to User.settings.
      # MINIMUM_VERSION is the minimum version of the cache that is acceptable to use as valid
      # data. If the cache is older than the minimum version, it will be reloaded. We might not need
      # these to always be in sync as features are developed to reduce the amount of reloading of data
      # for all users.
      CURRENT_VERSION = 1
      MINIMUM_VERSION = 1

      sig { params(user: ::User).void }
      def self.for(user)
        new(user)
      end

      sig { returns(::User) }
      attr_reader :user

      sig { returns(T.nilable(::String)) }
      memoize def analytics_tracking_id
        @analytics_tracking_id
      end

      sig { returns(T::Array[Copilot::Organization]) }
      memoize def copilot_organizations
        ids = @internal.fetch(:copilot_organization_ids, [])
        return live_copilot_organizations if ids.empty?

        ::Organization.where(id: ids).map do |org|
          Copilot::Organization.new(org)
        end
      end

      sig { returns(T::Boolean) }
      memoize def has_cb_access?
        @internal.dig(:plan_details, :has_cb_access) || false
      end

      sig { returns(T::Boolean) }
      memoize def has_ce_access?
        @internal.dig(:plan_details, :has_ce_access) || false
      end

      sig { returns(T::Boolean) }
      memoize def has_ci_access?
        @internal.dig(:plan_details, :has_ci_access) || false
      end

      sig { returns(T::Boolean) }
      memoize def has_free_access?
        @internal.dig(:plan_details, :has_free_access) || false
      end

      sig { returns(T::Boolean) }
      memoize def has_paid_access?
        @internal.dig(:plan_details, :has_paid_access) || false
      end

      sig { returns(T::Boolean) }
      memoize def has_paid_ci_access?
        has_ci_access? && has_paid_access?
      end

      sig { returns(T::Boolean) }
      memoize def has_copilot_access?
        has_paid_access? || has_free_access?
      end

      sig { returns(Symbol) }
      memoize def access_type
        @internal.dig(:plan_details, :access_type)&.to_sym || :NO_ACCESS
      end

      sig { returns(T::Boolean) }
      memoize def bing_github_chat_enabled?
        @internal.dig(:copilot_settings, :bing_github_chat_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def cli_enabled?
        @internal.dig(:copilot_settings, :cli_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def custom_models_enabled?
        @internal.dig(:copilot_settings, :custom_models_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def dotcom_chat_enabled?
        @internal.dig(:copilot_settings, :dotcom_chat_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def mobile_chat_enabled?
        @internal.dig(:copilot_settings, :mobile_chat_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def pr_summarizations_enabled?
        @internal.dig(:copilot_settings, :pr_summarizations_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def private_docs_enabled?
        @internal.dig(:copilot_settings, :private_docs_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def extensions_enabled?
        @internal.dig(:copilot_settings, :extensions_enabled) || false
      end

      private

      sig { params(user: ::User).void }
      def initialize(user)
        @user                  = user
        @analytics_tracking_id = T.let(user.analytics_tracking_id, T.nilable(String))
        @copilot_user          = T.let(Copilot::User.new(@user), Copilot::User)
        @internal              = T.let(Hash.new, T::Hash[Symbol, T.untyped])  # rubocop:disable Sorbet/ForbidTUntyped

        load_from_cache
      end

      sig { void }
      def load_from_cache
        cached_user = JSON.parse(@user.settings.get(:copilot_policy_data)).deep_symbolize_keys
        @internal = cached_user

        if cached_user.empty? || cached_user.fetch(:version, 0) < MINIMUM_VERSION
          reload_user_settings
        end
      end

      sig { void }
      def reload_user_settings
        @copilot_user.create_copilot_settings_cache(CURRENT_VERSION)
        @internal = JSON.parse(@user.settings.get(:copilot_policy_data)).deep_symbolize_keys
      end

      sig { returns(ActiveRecord::Relation) }
      memoize def copilot_seats
        Copilot::Seat.includes(:seat_assignment).where(assigned_user_id: @user.id)
      end

      sig { returns(T::Array[Copilot::Organization]) }
      memoize def live_copilot_organizations
        copilot_seats.map do |seat|
          next unless seat.seat_assignment.owner_type == "Organization"

          Copilot::Organization.new(seat.seat_assignment.owner)
        end.compact
      end
    end
  end
end
