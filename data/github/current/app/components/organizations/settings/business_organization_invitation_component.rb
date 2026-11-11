# typed: true
# frozen_string_literal: true

class Organizations::Settings::BusinessOrganizationInvitationComponent < ApplicationComponent
  attr_reader :invitation, :business, :organization, :terms_of_service

  def initialize(invitation:, organization:, terms_of_service:)
    @invitation = invitation
    @business = invitation.business
    @organization = organization
    @terms_of_service = terms_of_service
    @terms_of_service_corporate = terms_of_service.corporate?
  end

  # Public: Get the inviter login if the inviter exists, otherwise the
  # enterprise slug to be used as the target for a potential abuse report.
  #
  # Returns String.
  def report_target
    @invitation.inviter&.display_login || @business.slug
  end

  def terms_of_service_corporate?
    @terms_of_service_corporate
  end
end
