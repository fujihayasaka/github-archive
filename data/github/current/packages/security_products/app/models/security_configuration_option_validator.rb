# typed: true
# frozen_string_literal: true

class SecurityConfigurationOptionValidator < ActiveModel::Validator
  sig { returns(T::Hash[Symbol, T.class_of(SecurityProduct::Service::Options)]) }
  def columns
    options[:columns]
  end

  sig { params(config: SecurityConfiguration).void }
  def validate(config)
    columns.each do |column, options_class|
      enablement_column = column.to_s.chomp("_options")
      enablement_state = config.attributes[enablement_column]
      opts = options_class.new_from_hash(config.attributes[column.to_s])

      # If we just have default options, nothing to do
      next if opts.attributes == options_class.default_attributes

      attach_enablement_error(config, column, enablement_state) unless enablement_state == "enabled"
      attach_options_errors(config, column, opts) unless opts.valid?
    end
  end

  private

  sig { params(config: SecurityConfiguration, column: Symbol, opts: SecurityProduct::Service::Options).void }
  def attach_options_errors(config, column, opts)
    opts.errors.each do |err|
      config.errors.add(column, err)
    end
  end

  sig { params(config: SecurityConfiguration, column: Symbol, enablement_state: String).void }
  def attach_enablement_error(config, column, enablement_state)
    config.errors.add(
      column,
      message: "#{column.to_s.humanize} cannot be set when the feature is #{enablement_state.humanize(capitalize: false)}"
    )
  end
end
