# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class UserSpammyCheck < Platform::Loader
      if GitHub.spamminess_check_enabled?
        def self.load(user_id, viewer, show_spam_to_staff: true)
          return Promise.resolve(false) if viewer&.site_admin? && show_spam_to_staff

          self.for.load(user_id).then do |spammy|
            if viewer&.id == user_id
              false
            else
              spammy
            end
          end
        end

        def fetch(user_ids)
          spammy_user_ids = User.spammy.or(User.suspended).batched_scope(:id, values: user_ids).pluck(:id)
          spammy_user_ids.each_with_object(Hash.new(false)) do |user_id, result|
            result[user_id] = true
          end
        end
      else
        def self.load(user_id, viewer, show_spam_to_staff: true)
          Promise.resolve(false)
        end
      end
    end
  end
end
