# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryTrace2Test < GitHub::TestCase
  setup do
    @repo = create(:repository, :full_creation)
  end

  unless GitHub.enterprise?
    context "trace2 enabled" do
      test "indicates that trace2 is enabled for dotcom" do
        assert @repo.trace2_enabled?, "expected trace2 to be enabled"
      end

      test "instruments GitRPC calls with trace2 information" do
        puts(@repo.rpc.options[:trace2])
        assert @repo.rpc.options[:trace2].include?(:nw_repack),
          "repacking is not instrumented for trace2 (should be)"
      end
    end
  end

  if GitHub.enterprise?
    context "trace2 disabled" do
      test "indicates that trace2 is disabled" do
        refute @repo.trace2_enabled?, "expected trace2 to be disabled"
      end

      test "does not instrument GitRPC calls with trace2 information" do
        refute @repo.rpc.options.include?(:trace2),
          "trace2 is enabled for some commands (shouldn't be)"
      end
    end
  end
end
