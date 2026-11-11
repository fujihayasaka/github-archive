# typed: true
# frozen_string_literal: true

class BillingManagers::NewView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :organization, :rate_limited

  def rate_limited?
    !!rate_limited
  end
end
