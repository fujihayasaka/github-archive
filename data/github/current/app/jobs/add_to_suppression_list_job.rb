# typed: true
# frozen_string_literal: true

class AddToSuppressionListJob < ApplicationJob
  queue_as :add_to_suppression_list

  retry_on_dirty_exit

  # Add the user to the suppression list.
  #
  # user_id - The integer user id.
  #
  # Returns nothing.
  def perform(user_id)
    user = with_write { User.find_by(id: user_id) }
    return unless user

    GitHub.dogstats.time "suppression_list", tags: ["action:add_user", "via:job"] do
      with_write { SuppressionList.add_user(user) }
    end
  end
end
