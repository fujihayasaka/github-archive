# typed: true
# frozen_string_literal: true

module Notifyd::Publishing
  class RecipientGroups
    extend T::Sig

    attr_reader :groups

    sig { params(groups: T::Array[T::Hash[Symbol, T::Array[User]]]).void }
    def initialize(groups:)
      @groups = groups
    end

    sig { params(feature_flag: T.any(Flipper::Feature, Notifyd::SubjectAdapter::FeatureEnabled)).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def filter_for(feature_flag:)
      groups.inject([]) do |recipients, recipient_group|
        classified_users_ids = recipient_group[:users].filter_map do |user|
          user.id if feature_flag.enabled?(user)
        end
        recipients << { reason: recipient_group[:reason], user_ids: classified_users_ids } if classified_users_ids.any?

        recipients
      end
    end
  end
end
