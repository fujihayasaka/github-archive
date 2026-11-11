# rubocop:disable Style/FrozenStringLiteralComment
# DGit routes are used by GitRPC and ThreePCClient.
#
# These tests ensure the given class implements all of the methods
# that are required of a Route object.
module GitRPC
  class Protocol
    class DGit
      module RouteLintTest
        def dgit_route
          raise "When this module is included, you must implement dgit_route to return a route-like object"
        end

        def test_dgit_route_original_host
          refute_nil dgit_route.original_host
        end

        def test_dgit_route_host
          refute_nil dgit_route.host, "default value of host"
        end

        def test_dgit_route_host_can_be_changed
          the_route = dgit_route
          the_route.host = "different"
          assert_equal "different", the_route.host, "new value of host"
        end

        def test_dgit_route_resolved_host
          refute_nil dgit_route.resolved_host
        end

        def test_dgit_route_port
          assert_kind_of Integer, dgit_route.port
        end

        def test_dgit_route_path
          refute_nil dgit_route.path
        end
      end
    end
  end
end
