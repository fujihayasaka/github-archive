# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Settings::LegalNameComponent < ApplicationComponent
  def initialize(sponsorable:)
    @sponsorable = sponsorable
    @listing = @sponsorable&.sponsors_listing
  end

  private

  def render?
    @sponsorable.present? &&
      @listing.present? &&
      @listing.legal_name_changeable?
  end

  def legal_name
    @listing.legal_name
  end

  def legal_name_label
    if @sponsorable.user?
      "Full legal name"
    else
      "Organization name"
    end
  end
end
