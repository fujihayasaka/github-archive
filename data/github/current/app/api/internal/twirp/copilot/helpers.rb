# typed: strict
# frozen_string_literal: true

require "monolith-twirp-copilot-users"

module Api::Internal::Twirp::Copilot
  module Helpers
    sig { params(access_type: Symbol).returns(Integer) }
    def twirp_access_type(access_type)
      GitHub.dogstats.increment("copilot.twirp_access_type", tags: { access_type: access_type })
      case access_type
      when :NO_ACCESS, :ENTERPRISE_MANAGED, :BILLING_LOCKED
        MonolithTwirp::Copilot::Users::V1::AccessType::ACCESS_TYPE_INVALID
      else
        "MonolithTwirp::Copilot::Users::V1::AccessType::ACCESS_TYPE_#{access_type}".constantize
      end
    rescue NameError
      GitHub.dogstats.increment("copilot.twirp_access_type.error", tags: { access_type: access_type })
      MonolithTwirp::Copilot::Users::V1::AccessType::ACCESS_TYPE_INVALID
    end
  end
end
