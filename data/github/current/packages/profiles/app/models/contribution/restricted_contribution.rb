# typed: true
# frozen_string_literal: true

# Wraps a Contribution and only exposes data that can be
# viewed publicly. This is used to show contributions like FirstRepository
# and FirstIssue to people who don't have access to the contribution's subject.
class Contribution::RestrictedContribution
  include GitHub::Relay::GlobalIdentification

  delegate :occurred_at, :occurred_on, :user, :contributions_count, :contribution_class, :url, to: :@contribution

  def initialize(contribution)
    @contribution = contribution
  end

  def restricted?
    true
  end
end
