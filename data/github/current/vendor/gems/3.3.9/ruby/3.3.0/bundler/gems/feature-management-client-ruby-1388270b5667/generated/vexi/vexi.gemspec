# -*- encoding: utf-8 -*-
# stub: vexi 0.2.44 ruby lib

Gem::Specification.new do |s|
  s.name = "vexi".freeze
  s.version = "0.2.44".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "github_repo" => "ssh://github.com/github/feature-management-client-ruby" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["github/feature-management".freeze]
  s.date = "2022-01-01"
  s.description = "Vexi is short for \"vexillology\" which is the study of flags.".freeze
  s.files = ["lib/vexi.rb".freeze, "lib/vexi/abstract_entity_service.rb".freeze, "lib/vexi/actor.rb".freeze, "lib/vexi/actor_collection.rb".freeze, "lib/vexi/adapter.rb".freeze, "lib/vexi/adapters/array_actor_collection.rb".freeze, "lib/vexi/adapters/file_adapter.rb".freeze, "lib/vexi/adapters/in_memory_adapter.rb".freeze, "lib/vexi/adapters/monolith_optimized_feature_flag_data_adapter.rb".freeze, "lib/vexi/builder.rb".freeze, "lib/vexi/builders/adapter_builder.rb".freeze, "lib/vexi/builders/cache_builder.rb".freeze, "lib/vexi/builders/circuit_breaker_builder.rb".freeze, "lib/vexi/builders/custom_gates_evaluator_builder.rb".freeze, "lib/vexi/cache.rb".freeze, "lib/vexi/cache_config.rb".freeze, "lib/vexi/caches/in_memory.rb".freeze, "lib/vexi/circuit_breaker_config.rb".freeze, "lib/vexi/client.rb".freeze, "lib/vexi/configuration.rb".freeze, "lib/vexi/custom_gates_evaluator.rb".freeze, "lib/vexi/custom_gates_evaluators/serial_gate_and_actor_evaluator.rb".freeze, "lib/vexi/entity.rb".freeze, "lib/vexi/errors.rb".freeze, "lib/vexi/errors/circuit_breaker_open_error.rb".freeze, "lib/vexi/errors/entity_not_found_error.rb".freeze, "lib/vexi/errors/feature_flag_not_found_error.rb".freeze, "lib/vexi/errors/file_not_found_error.rb".freeze, "lib/vexi/errors/segment_not_found_error.rb".freeze, "lib/vexi/errors/validation_error.rb".freeze, "lib/vexi/hash_actor_collection.rb".freeze, "lib/vexi/instrumentation_context.rb".freeze, "lib/vexi/instrumenter.rb".freeze, "lib/vexi/models/feature_flag.rb".freeze, "lib/vexi/models/get_entity_response.rb".freeze, "lib/vexi/models/get_feature_flag_response.rb".freeze, "lib/vexi/models/get_segment_response.rb".freeze, "lib/vexi/models/segment.rb".freeze, "lib/vexi/non_actor_gate_evaluator.rb".freeze, "lib/vexi/notifications.rb".freeze, "lib/vexi/observability/notification.rb".freeze, "lib/vexi/observability/null.rb".freeze, "lib/vexi/services/feature_flag_service.rb".freeze, "lib/vexi/services/segment_service.rb".freeze, "lib/vexi/version.rb".freeze]
  s.homepage = "http://www.github.com/github/feature-management-client-ruby".freeze
  s.licenses = ["Nonstandard".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.0.0".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Vexi is a Ruby Client for feature flag checks".freeze

  s.installed_by_version = "3.5.22".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<activesupport>.freeze, [">= 7.0".freeze])
  s.add_runtime_dependency(%q<feature_management_feature_flags>.freeze, [">= 1.6".freeze, "< 1.8".freeze])
  s.add_runtime_dependency(%q<fnv>.freeze, ["= 0.2.0".freeze])
  s.add_runtime_dependency(%q<zache>.freeze, ["= 0.13.2".freeze])
end
