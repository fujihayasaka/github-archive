# typed: true
# frozen_string_literal: true

class Businesses::FailedInvitationsView < Businesses::QueryView

  attr_reader :invitations, :business, :organizations, :sort

  def initialize(**args)
    super(args)
    @business = args[:business]
    @invitations = args[:invitations]
  end

  def filter_map
    BusinessesHelper::FAILED_INVITATIONS_QUERY_FILTERS
  end
end
