# typed: strict
# frozen_string_literal: true

# CodeScanning::SecurityConfigurationOptions defines the options related to
# Code Scanning which are stored in the database as JSON when creating a
# SecurityConfiguration.
#
# This builds off the service options for AutoCodeQL, but has additional
# options not related to default setup.
module CodeScanning
  class SecurityConfigurationOptions < CodeScanning::AutoCodeql::Options
    # Options are stored as class instance variables, so inheriting from
    # CodeScanning::AutoCodeql::Options _doesn't_ mean that the @options
    # variable for this class will contain the options from the parent class.
    # Instead, we need to explicitly copy the options from the parent class.
    @options = T.let(
      CodeScanning::AutoCodeql::Options.options.dup,
      T::Hash[Symbol, T::Hash[Symbol, T.untyped]])

    # If you add additional options here, you should almost certainly also
    # add their keys to SecurityConfiguration#code_scanning_general_options
    option :allow_advanced, default: false
    validates :allow_advanced, allow_nil: false, inclusion: { in: [true, false] }
  end
end
