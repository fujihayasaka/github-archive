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
    profile&.bio.present?
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
    # if they have any repos that are not their profile repo, they have created a repo
    repositories.where.not(name: display_login).count > 0
  end
end
