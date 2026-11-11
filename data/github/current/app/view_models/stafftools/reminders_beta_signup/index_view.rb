# typed: true
# frozen_string_literal: true

class Stafftools::RemindersBetaSignup::IndexView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :memberships, :slack_installations, :capable_internal_apps

  def signups
    @signups ||= begin
      memberships.select(&:member).map do |membership|
        Signup.new(
          membership,
          slack_installations[membership.member],
        )
      end
    end
  end

  class Signup
    attr_reader :membership, :slack_installation
    def initialize(membership, slack_installation)
      @membership = membership
      @slack_installation = slack_installation
    end

    def organization
      @organization ||= membership.member
    end

    def submitter
      @submitter ||= membership.actor || User.ghost
    end

    def submitted_at
      membership.created_at.to_date.iso8601
    end
  end
end
