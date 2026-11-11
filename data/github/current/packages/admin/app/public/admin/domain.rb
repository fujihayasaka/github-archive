# typed: strict
# frozen_string_literal: true

module Admin
  class Domain < GH::Domain::Base
    accessor Admin::Domain::Businesses
    accessor Admin::Domain::BusinessUserAccounts
  end
end
