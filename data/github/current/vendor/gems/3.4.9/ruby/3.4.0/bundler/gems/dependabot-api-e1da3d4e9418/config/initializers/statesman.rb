# frozen_string_literal: true

Statesman.configure do
  storage_adapter(Statesman::Adapters::ActiveRecord)
  # Enabled for MySQL by default, but since we use Trilogy we need to explicitly
  # opt in.
  enable_mysql_gaplock_protection
end
