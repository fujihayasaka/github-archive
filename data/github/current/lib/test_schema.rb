# typed: true
# frozen_string_literal: true
# rubocop:disable GitHub/DoNotCallMethodsOnActiveRecordBase

class TestSchema
  attr_reader :configs

  def initialize(configs)
    @configs = configs.map(&:symbolize_keys)
  end

  def needs_load?
    original_db_config = ActiveRecord::Base.connection_db_config

    configs.any? { |config| !schema_up_to_date?(config) }
  ensure
    ActiveRecord::Base.establish_connection(original_db_config) if original_db_config
  end

  def schema_up_to_date?(db_config)
    ActiveRecord::Base.establish_connection(db_config)

    return false unless ActiveRecord::Base.connection_pool.internal_metadata.enabled?

    # We can't use `ActiveRecord::InternalMetadata.table_exists?` here because that goes
    # to the schema cache if it exists, and the schema cache is not guaranteed to be up-to-date.

    ActiveRecord::Base.connection_pool.with_connection do |conn|
      return false unless conn.table_exists?(ActiveRecord::Base.connection_pool.internal_metadata.table_name)
    end

    structure_paths = Array(db_config[:structure]).map { |structure| Rails.root.join("db", structure) }
    schema_hash = Digest::SHA256.hexdigest(structure_paths.map { |x| File.read(x) }.join)

    ActiveRecord::Base.connection_pool.internal_metadata[:schema_hash] == schema_hash
  end
end
