require "ostruct"

class Configuration < OpenStruct
  def self.for(config_file, options = {})
    build(Rails.application.config_for(config_file), options)
  end

  def self.build(*args)
    new(*args).tap(&:validate!)
  end

  def initialize(config, options = {})
    @options = options
    @config  = config.symbolize_keys.compact.reverse_merge(defaults)

    super(@config)
  end

  def validate!
    raise MissingKeysError.new(missing_keys) if missing_keys.any?
  end

  private

  # Sets the HMAC key used to verify request bodies sent to the Internal API.
  attr_accessor :dependency_graph_api_hmac_keys

  # Sets the HMAC key used to communicate with dependency-graph-platform
  attr_accessor :dependency_graph_platform_hmac_keys

  attr_reader :config, :options

  def required_keys
    Array(options[:require])
  end

  def missing_keys
    @missing_keys ||= required_keys.select { |key| config[key].blank? }
  end

  def defaults
    options.fetch(:defaults, {})
  end

  class MissingKeysError < ArgumentError
    def initialize(keys)
      @keys = keys
      super
    end

    def message
      "Missing configuration keys: '#{@keys}'"
    end
  end
end
