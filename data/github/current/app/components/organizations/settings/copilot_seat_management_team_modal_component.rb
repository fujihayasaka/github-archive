# typed: strict
# frozen_string_literal: true

class Organizations::Settings::CopilotSeatManagementTeamModalComponent < ApplicationComponent

  sig { params(organization: ::Organization, page_param: Integer, page_size: Integer).void }
  def initialize(organization, page_param: 2, page_size: 10)
    @organization = organization
    @page_param = page_param
    @page_size = page_size
    @orig_page = T.let(page_param.to_i, Integer)
  end

  sig { returns(T::Boolean) }
  def show_pagination?
    true
  end
end
