# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "github/sorbet/module_patch"

require "github/sorbet/runtime"

require "github/sorbet/promise"
require "github/sorbet/promises"
require "github/sorbet/iopromise"
require "github/sorbet/twirp"

if Rails.env.test?
  # Raise TypeError exceptions in tests and tell Sorbet we are running tests
  GitHub::Sorbet::Runtime.start_test_type_checking!
elsif ENV["STAFF_ENVIRONMENT"] == "review-lab" || rand(100) < ENV["GITHUB_RUNTIME_TYPE_CHECKING_PERCENTAGE"].to_i
  # Report errors to Sentry but don't halt execution by raising
  GitHub::Sorbet::Runtime.silently_report_errors!
else
  # Remove type checking entirely from non-test environments by default
  GitHub::Sorbet::Runtime.skip_type_checks_by_default!
end

# See https://github.com/sorbet/sorbet/blob/master/gems/sorbet-runtime/lib/types/compatibility_patches.rb#L54-L95
::Method.prepend(T::CompatibilityPatches::MethodExtensions)
