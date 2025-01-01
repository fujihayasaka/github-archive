# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  ENABLEMENT_FAILURES_JSON_PATH = Rails.root.join("config", "code_security_configuration_failures.json")

  def self.enablement_failures_map
    return @enablement_failures_map if instance_variable_defined?(:@enablement_failures_map)
    @enablement_failures_map = begin
      T.let(
        JSON.parse(File.read(ENABLEMENT_FAILURES_JSON_PATH))["failures"],
        T::Hash[String, T.untyped]
      )
    rescue JSON::ParserError, Errno::ENOENT => e
      Failbot.report(e)
      {}
    end
  end
end
