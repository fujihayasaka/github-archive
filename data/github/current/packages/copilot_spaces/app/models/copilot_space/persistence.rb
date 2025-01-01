# typed: true
# frozen_string_literal: true

class CopilotSpace
  class Persistence < T::Struct
    const :copilot_space, CopilotSpace
    const :current_user, User
    const :cap_filter, ConditionalAccess::Filter
    const :action, Symbol

    def self.save(copilot_space:, current_user:, cap_filter:, action:)
      new(copilot_space:, current_user:,  cap_filter:, action:).save
    end

    def save
      validator = CopilotSpace::CapValidator.new(current_user:, cap_filter:, copilot_space:)
      validator.validate_space(action)

      copilot_space.save
    end

    private

    def assign_user_and_cap(copilot_space)
      copilot_space.current_user = current_user
      copilot_space.cap_filter = cap_filter
    end
  end
end
