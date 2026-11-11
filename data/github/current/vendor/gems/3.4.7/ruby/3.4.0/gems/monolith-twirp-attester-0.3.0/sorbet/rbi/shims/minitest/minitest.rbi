# typed: true

# Shims-in the `assert_matches_snapshot` method from the `minitest-snapshots` gem.
module Minitest
  class Test
    sig { params(value: T.anything, snapshot_name: T.anything).returns(TrueClass) }
    def assert_matches_snapshot(value, snapshot_name = nil); end;
  end
end
