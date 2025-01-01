# typed: true
# frozen_string_literal: true

module User::ZeroUserDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ::User }

  sig { returns(T::Boolean) }
  def has_avatar?
    all_avatars.any? { |avatar| avatar.present? }
  end

  sig { returns(T::Boolean) }
  def has_created_profile?
    user_profile = profile
    return false unless user_profile

    %i[name email blog company location bio].any? { |attr| user_profile[attr].present? }
  end

  sig { returns(T::Boolean) }
  def has_customized_account?
    has_avatar? || has_created_profile?
  end

  sig { returns(T::Boolean) }
  def has_tried_copilot?
    # TODO: future PR will determine best course to take here
    # previous implementation was checking threads and messages in copilot API
    # but was causing sever spikes in the copilot API

    false
  end

  sig { returns(T::Boolean) }
  def has_created_repo?
    repositories.any?
  end
end
