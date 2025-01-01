# typed: true
# frozen_string_literal: true

require "test_helper"

class Repositories::DomainTest < GitHub::TestCase
  include GitHub::DatabaseQueryWarningsTestHelpers
  include PerformanceTestHelpers

  setup do
    act_as(@user)
    @domain = T.let(Repositories::Domain.new, T.nilable(Repositories::Domain))
  end

  teardown do
    GitHub::CurrentTenant.remove
  end

  sig { returns(Repositories::Domain) }
  def domain
    T.must(@domain)
  end
end
