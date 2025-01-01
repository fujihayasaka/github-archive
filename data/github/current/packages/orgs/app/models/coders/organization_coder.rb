# typed: true
# frozen_string_literal: true

module Coders
  class OrganizationCoder < Coders::Base
    include Coders::UserCoder::Shared

    data_accessors \
      :destroy_owners_team_attempted_at,
      :migrated_all_legacy_contributors_at,
      :updated_team_privacy_at,
      :completed_onboarding_tasks,
      :show_onboarding_tasks

    def destroy_owners_team_attempted_at
      time(data[:destroy_owners_team_attempted_at])
    end

    def migrated_all_legacy_contributors_at
      time(data[:migrated_all_legacy_contributors_at])
    end

    def updated_team_privacy_at
      time(data[:updated_team_privacy_at])
    end

    sig { returns(T::Array[Symbol]) }
    def completed_onboarding_tasks
      data[:completed_onboarding_tasks]&.map(&:to_sym) || []
    end

    def show_onboarding_tasks?
      data[:show_onboarding_tasks]
    end
  end
end
