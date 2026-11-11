# typed: true
# frozen_string_literal: true

module Configsd::DevServerNotice
  extend GH::Decorator
  extend Scientist

  sig { override.params(decorable: GH::Decorator::Decorable, method_name: Symbol).void }
  def self.decorate_method(decorable, method_name)
    decorate(decorable, method_name) do |*args, **kwargs, &block|
      super(*args, **kwargs, &block)
    rescue Faraday::ConnectionFailed => e
      raise Faraday::ConnectionFailed, <<~MSG.squish
        Could not connect to the Configsd development server.
        Please ensure that the Configsd server is running by executing `script/configsd-server` in a separate terminal
        or disabling the configsd_entries_experiment feature flag.
      MSG
    end
  end
end
