# typed: true
# frozen_string_literal: true

class GitHub::Migration
  def self.inherited(subclass)
    path = T.must(caller_locations.first&.path)
    where_it_is_used = Pathname(path).relative_path_from(Rails.root)

    puts <<~MESSAGE
      \e[33mHey! Your migration needs a small adjustment before it can be run.\e[0m

      1. Open #{where_it_is_used}
      2. Replace `GitHub::Migration` with `ActiveRecord::Migration[4.2]`

      Going forward, you can create migrations with the Rails migration generator: https://guides.rubyonrails.org/active_record_migrations.html#creating-a-standalone-migration
    MESSAGE

    exit 1
  end
end
