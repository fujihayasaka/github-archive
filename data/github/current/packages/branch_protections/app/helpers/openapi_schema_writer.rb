# typed: true
# frozen_string_literal: true

class OpenapiSchemaWriter < SchemaWriter

  sig { params(dry: T::Boolean).void }
  def initialize(dry)
    @file_type = :openapi
    @dry = dry
    super()
  end

  sig { params(dry: T::Boolean).returns(OpenapiSchemaWriter) }
  def self.instance(dry)
    @instance ||= new(dry)
  end
end
