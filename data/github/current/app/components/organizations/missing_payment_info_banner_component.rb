# typed: true
# frozen_string_literal: true

# Used to render a warning notice banner on a standalone organization on a paid plan, and in a
# state where it needs to add its payment information.
class Organizations::MissingPaymentInfoBannerComponent < ApplicationComponent
  extend T::Sig

  sig { params(organization: T.nilable(Organization), current_user: T.nilable(User)).void }
  def initialize(organization:, current_user:)
    @organization = organization
    @current_user = current_user
  end

  private

  sig { returns(T.nilable(Organization)) }
  attr_reader :organization

  sig { returns(T.nilable(User)) }
  attr_reader :current_user

  sig { returns(T::Boolean) }
  def render?
    return false unless GitHub.billing_enabled?

    organization = self.organization
    return false unless organization.present?

    current_user = self.current_user
    return false unless current_user.present?

    return false if organization.invoiced?
    return false unless organization.beneficiary?

    organization.adminable_by?(current_user) || organization.billing_manager?(current_user)
  end
end
