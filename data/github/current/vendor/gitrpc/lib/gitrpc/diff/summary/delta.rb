# rubocop:disable Style/FrozenStringLiteralComment
module GitRPC
  class Diff
    class Summary
      class Delta < ::GitRPC::Diff::Delta
        include GitRPC::Diff::Summary::Common

        attr_reader :additions
        attr_reader :deletions

        def initialize(additions: 0, deletions: 0, **args)
          super(**args)

          if additions.nil? ^ deletions.nil?
            raise ArgumentError, "Both :additions and :deletions need to either be nil (for binary changes) or non-nil (for non-binary changes)"
          end

          @additions = additions
          @deletions = deletions
        end

        def binary?
          additions.nil? && deletions.nil?
        end

        def ==(other)
          case other
          when ::GitRPC::Diff::Summary::Delta
            super && additions == other.additions && deletions == other.deletions
          when ::GitRPC::Diff::Delta
            super
          else
            false
          end
        end
      end
    end
  end
end
