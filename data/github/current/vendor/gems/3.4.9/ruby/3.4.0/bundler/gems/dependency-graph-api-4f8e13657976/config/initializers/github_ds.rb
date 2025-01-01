require "github/kv"

GitHub::KV.configure do |config|
  config.table_name = "dg_key_values"
end
