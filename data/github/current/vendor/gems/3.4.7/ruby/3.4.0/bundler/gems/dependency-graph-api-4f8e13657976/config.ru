# This file is used by Rack-based servers to start the application.

require_relative "config/environment"
require_relative "lib/dependency_graph/flamegraph_middleware"
require_relative "lib/dependency_graph/memory_profiler_middleware"
require_relative "lib/dependency_graph/sql_queries_middleware"
require_relative "lib/dependency_graph/trace_profiler_middleware"

use DependencyGraph::FlamegraphMiddleware
use DependencyGraph::MemoryProfilerMiddleware
use DependencyGraph::SQLQueriesMiddleware
use DependencyGraph::TraceProfilerMiddleware

run Rails.application
