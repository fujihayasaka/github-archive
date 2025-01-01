# typed: true
# frozen_string_literal: true

module TwoFactorRequirement
  autoload :Queries, "two_factor_requirement/queries"
  autoload :Reason, "two_factor_requirement/reason"
  autoload :Updater, "two_factor_requirement/updater"
end
