# typed: true
# frozen_string_literal: true

# Protecting at the ActiveRecord level for when GitHub is in read_only mode.
#
# This provides an additional layer of protection beyond the connection level
# read_only mode.  Note that as of early 2016, connection level read only
# mode is NOT respected in dev or test environments, but the ActiveRecord
# level read only mode is respected.
#
# See also https://thehub.github.com/engineering/development-and-ops/mysql/migrations/#multi-database-configuration for
# more documentation on GitHub's database and read/write replication setup.
module GitHub::ActiveRecordReadonlyMode
  extend T::Helpers
  requires_ancestor { ActiveRecord::Base }

  # Check GitHub.read_only mode when determining if a record is read_only?
  #
  # See also http://apidock.com/rails/v3.2.13/ActiveRecord/Base/readonly%3F
  #
  # Returns a Boolean
  def readonly?
    return true if GitHub.read_only?
    super
  end

  # Override default destroy behavior to raise if GitHub is in read_only mode
  def destroy
    raise ActiveRecord::ReadOnlyRecord if GitHub.read_only?
    super
  end

  # Override default delete behavior to raise if GitHub is in read_only mode
  def delete
    raise ActiveRecord::ReadOnlyRecord if GitHub.read_only?
    super
  end

  def self.initialize
    ActiveRecord::Base.prepend(GitHub::ActiveRecordReadonlyMode)
  end
end
