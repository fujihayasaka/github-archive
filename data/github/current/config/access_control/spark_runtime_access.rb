# typed: true
# frozen_string_literal: true

class Api::AccessControl < Egress::AccessControl
  define_access :runtime_write_loaded do |access|
    access.ensure_context :user, :resource
    access.allow :spark_runtime_telemetry_writer
  end
end
