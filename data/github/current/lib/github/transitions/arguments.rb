# typed: strict
# frozen_string_literal: true

require "optparse"

module GitHub
  module Transitions
    # Helper class for transitions to parse and access arguments.
    # Example how to create an instance:
    #
    #    arguments = GitHub::Transitions::Arguments.parse(ARGV)
    #    GitHub::Transitions::SomeRandomTransition.new(arguments)
    #
    # Then an instance is passed to a transition instance where it
    # can be accessed via the `arguments` reader. To read parse values,
    # the random access method can be used:
    #
    #    arguments[:foo] # returns what was passed via `--foo=bar`
    #
    # The class supports a series of default arguments, see below for the
    # list. If you want to specify your own custom arguments, you can pass
    # them to the initializer:
    #
    #    GitHub::Transitions::Arguments.parse(ARGV,
    #      additional_arguments: %w(foo)
    #    )
    #
    # Default arguments parsed for any instance:
    #
    # - `write`              - Enables writes, defaults to false,
    #                          pass `--write` to enable.
    # - `verbose`            - Log verbose output, defaults to true.
    # - `start_id`           - ID to start processing, default for database
    #                          table iterations is `MIN(table.id)`.
    # - `end_id`             - ID to end processing, default for database
    #                          table iterations is `MAX(table.id)`.
    # - `read_batch_size`    - Number of rows to read at a time, default for
    #                          database table iterations is
    #                          `DEFAULT_READ_BATCH_SIZE`.
    # - `process_batch_size` - Number of rows to process at a time, default for
    #                          database table iterations is
    #                          `DEFAULT_PROCESS_BATCH_SIZE`.
    # - `workers`            - Worker count for parallelization, default for
    #                          custom iterators is 1 (disabling
    #                          parallelization). For databse table iterations,
    #                          the default is `DEFAULT_WORKER_COUNT` defined in
    #                          the `Iterators::DatabaseTable` class. The maximum
    #                          is `MAX_WORKER_COUNT` defined in the same class.
    #
    class Arguments

      DEFAULT_VALUE_DRY_RUN = true

      # Transitions in enterprise run as part of release upgrades. During
      # such operations, verbose log output is not helpful but can slow
      # transition execution significantly.
      DEFAULT_VALUE_VERBOSE = false

      sig do
        params(args: T::Hash[Symbol, T.untyped]).void
      end
      def initialize(args = {})
        args[:dry_run] = DEFAULT_VALUE_DRY_RUN if args[:dry_run].nil?
        args[:verbose] = DEFAULT_VALUE_VERBOSE if args[:verbose].nil?

        @parsed_args = T.let(args.freeze, T::Hash[Symbol, T.untyped])
      end

      sig do
        params(name: Symbol).returns(T.untyped)
      end
      def [](name)
        @parsed_args[name]
      end

      sig { returns(String) }
      def to_s
        @parsed_args.to_s
      end

      sig do
        params(
          argv: T::Array[String],
          additional_arguments: T::Array[String]
        ).returns(GitHub::Transitions::Arguments)
      end
      def self.parse(argv, additional_arguments: [])
        options = {}
        OptionParser.new do |opts|
          opts.on("-w", "--write", "Enable writes for the transition") do
            options[:write] = true
          end
          opts.on("-v", "--verbose", "Log verbose output") do
            options[:verbose] = true
          end
          opts.on("--start_id ID", Integer, "ID to start processing") do |id|
            options[:start_id] = id
          end
          opts.on("--end_id ID", Integer, "ID to end processing") do |id|
            options[:end_id] = id
          end
          opts.on("--read_batch_size SIZE", Integer, "Number of rows to read at a time") do |size|
            options[:read_batch_size] = size
          end
          opts.on("--process_batch_size SIZE", Integer, "Number of rows to process at a time") do |size|
            options[:process_batch_size] = size
          end
          opts.on("--workers COUNT", Integer, "Worker count") do |count|
            options[:workers] = count
          end
          additional_arguments.each do |arg|
            opts.on("--#{arg} VALUE", arg.titleize) do |value|
              options[arg.to_sym] = value
            end
          end
        end.parse!(argv)

        options.merge!(dry_run: !options[:write]) if options.key?(:write)

        new(options)
      end
    end
  end
end
