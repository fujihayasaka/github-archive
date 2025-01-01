# typed: false
# frozen_string_literal: true

module GitHub
  # GitHub::RenameColumn helps us rename columns on ActiveRecord models in the
  # cases where we're unable or unwilling to migrate the table in question to
  # rename the column.
  #
  # For example, to rename the column 'watcher_count' on the Repository model
  # to 'stargazer_count' to better represent what data the column actually
  # stores, you'd put some code like this in app/models/repository.rb:
  #
  #     extend GitHub::RenameColumn
  #     rename_column :watcher_count => :stargazer_count
  #
  # This sets up a #stargazer_count and #stargazer_count= methods on Repository
  # that do what you'd expect. It also redefines #watcher_count and
  # #watcher_count= to raise whenever they are called. This is a great way to
  # catch calls to the old method name in CI and in production.
  #
  module RenameColumn
    OldColumnNameUsed = Class.new(NoMethodError)

    def rename_column(columns)
      columns.each_pair do |old_name, new_name|
        format_args = {
          old_name: old_name,
          new_name: new_name,
          klass: self.name,
        }
        class_eval sprintf(<<-'RUBY', format_args), __FILE__, __LINE__ + 1
          def %{new_name}
            read_attribute(:%{old_name})
          end

          def %{new_name}=(value)
            write_attribute(:%{old_name}, value)
          end

          def %{old_name}=(value)
            if caller[1].include?("lib/active_record/base.rb")
              return write_attribute(:%{old_name}, value)
            end

            raise GitHub::RenameColumn::OldColumnNameUsed,
              "Don't use %{klass}#%{old_name}= to refer to the %{old_name} column. Use #%{new_name}= instead"
          end

          def %{old_name}
            if caller[1].match(/lib\/active_(record|model)\/dirty.rb/)
              # ActiveRecord::Dirty#attribute_change calls this method to read the
              # value of the attribute. We can't raise an exception here or all
              # saves of these records would fail.
              return read_attribute(:%{old_name})
            end

            raise GitHub::RenameColumn::OldColumnNameUsed,
              "Don't use %{klass}#%{old_name} to refer to the %{old_name} column. Use #%{new_name} instead."
          end
        RUBY
      end
    end
  end
end
