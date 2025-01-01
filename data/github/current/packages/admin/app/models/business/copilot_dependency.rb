# typed: strict
# frozen_string_literal: true

# Creating empty associations to ensure that code paths that refer to either User or Business do not fail
module Business::CopilotDependency
  include GitHub::Memoizer
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Business }

  sig { returns(Integer) }
  def copilot_max_seats
    return copilot_business.copilot_max_seats if self.persisted?
    Copilot::COPILOT_ENTERPRISE_TEAM_MAX_SEATS_DEFAULT
  end

  sig { params(value: Integer).void }
  def copilot_max_seats=(value)
    return unless self.persisted? # no op - requires a persisted business
    copilot_business.copilot_max_seats = value
  end

  sig { returns(Copilot::Business) }
  memoize def copilot_business
    business = T.cast(self, ::Business)
    Copilot::Business.new(business)
  end
end
