# typed: strict
# frozen_string_literal: true

class Sponsors::StaffViewBannerComponent < ApplicationComponent
  class Context < T::Enum
    enums do
      Dashboard = new
      OrganizationInsights = new
    end
  end

  sig { params(account_login: String, context: Context).void }
  def initialize(account_login:, context:)
    @account_login = account_login
    @context       = context
  end

  private

  sig { returns(String) }
  attr_reader :account_login

  sig { returns(Context) }
  attr_reader :context

  sig { returns(String) }
  def page_name
    this_context = context

    case this_context
    when Context::Dashboard
      "dashboard"
    when Context::OrganizationInsights
      "organization insights"
    else
      T.absurd(this_context)
    end
  end
end
