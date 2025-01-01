# typed: true
# frozen_string_literal: true

module Coders
  class RepositoryCoder < Coders::Base
    data_accessors :code_search_enabled,
                   :created_by_user_id,
                   :deleted_at,
                   :deleted_by_user_id,
                   :lock_reason,
                   :primary_language_name,
                   :created_for_demo_by_gh,
                   :displayed_onboarding_tasks,
                   :completed_onboarding_tasks,
                   :restorable

    def created_by_user_id
      object = data[:created_by_user_id]
      object.respond_to?(:id) ? object.id : object
    end

    def deleted_at
      time data[:deleted_at]
    end

    def primary_language_name
      object = data[:primary_language_name]
      object.respond_to?(:name) ? object.name : object
    end

    sig { returns(T::Boolean) }
    def created_for_demo_by_gh?
      object = data[:created_for_demo_by_gh]
      return object if object.eql?(true)

      false
    end

    sig { returns(T::Array[Symbol]) }
    def completed_onboarding_tasks
      data[:completed_onboarding_tasks]&.map(&:to_sym) || []
    end

    sig { returns(T::Boolean) }
    def displayed_onboarding_tasks?
      object = data[:displayed_onboarding_tasks]
      object.eql?(true)
    end

    sig { returns(T::Boolean) }
    def restorable?
      object = data[:restorable]
      # Default restorable to true. An explicit false setting is required to make it false.
      return false if object.eql?(false)
      true
    end
  end
end
