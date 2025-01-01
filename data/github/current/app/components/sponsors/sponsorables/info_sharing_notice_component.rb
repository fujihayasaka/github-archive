# typed: strict
# frozen_string_literal: true

class Sponsors::Sponsorables::InfoSharingNoticeComponent < Primer::Component
  sig { params(business: T::Boolean, system_arguments: T.untyped).void }
  def initialize(business: false, **system_arguments)
    @business = business
    @system_arguments = system_arguments
  end

  private

  sig { returns(T::Boolean) }
  def render?
    GitHub.sponsors_enabled?
  end

  sig { returns(T::Boolean) }
  def business?
    @business
  end

  sig { returns(String) }
  def shared_information
    if business?
      "sponsorship amount, country, region, and business tax status"
    else
      "sponsorship amount, country, and region"
    end
  end
end
