# -*- encoding: utf-8 -*-
# stub: pitchfork 0.16.0 ruby lib
# stub: ext/pitchfork_http/extconf.rb

Gem::Specification.new do |s|
  s.name = "pitchfork".freeze
  s.version = "0.16.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Jean Boussier".freeze]
  s.bindir = "exe".freeze
  s.date = "1980-01-02"
  s.description = "`pitchfork` is a preforking HTTP server for Rack applications designed\nto minimize memory usage by maximizing Copy-on-Write performance.".freeze
  s.email = ["jean.boussier@gmail.com".freeze]
  s.executables = ["pitchfork".freeze]
  s.extensions = ["ext/pitchfork_http/extconf.rb".freeze]
  s.files = [".devcontainer/devcontainer.json".freeze, ".git-blame-ignore-revs".freeze, ".gitattributes".freeze, ".github/workflows/ci.yml".freeze, ".gitignore".freeze, ".ruby-version".freeze, "CHANGELOG.md".freeze, "COPYING".freeze, "Dockerfile".freeze, "Gemfile".freeze, "LICENSE".freeze, "README.md".freeze, "Rakefile".freeze, "benchmark/README.md".freeze, "benchmark/cow_benchmark.rb".freeze, "docs/Application_Timeouts.md".freeze, "docs/CONFIGURATION.md".freeze, "docs/DESIGN.md".freeze, "docs/FORK_SAFETY.md".freeze, "docs/MIGRATING_FROM_UNICORN.md".freeze, "docs/PHILOSOPHY.md".freeze, "docs/REFORKING.md".freeze, "docs/SIGNALS.md".freeze, "docs/TUNING.md".freeze, "docs/WHY_MIGRATE.md".freeze, "examples/constant_caches.ru".freeze, "examples/echo.ru".freeze, "examples/hello.ru".freeze, "examples/nginx.conf".freeze, "examples/pitchfork.conf.minimal.rb".freeze, "examples/pitchfork.conf.rb".freeze, "examples/pitchfork.conf.service.rb".freeze, "examples/unicorn.socket".freeze, "exe/pitchfork".freeze, "ext/pitchfork_http/CFLAGS".freeze, "ext/pitchfork_http/c_util.h".freeze, "ext/pitchfork_http/child_subreaper.h".freeze, "ext/pitchfork_http/common_field_optimization.h".freeze, "ext/pitchfork_http/epollexclusive.h".freeze, "ext/pitchfork_http/ext_help.h".freeze, "ext/pitchfork_http/extconf.rb".freeze, "ext/pitchfork_http/global_variables.h".freeze, "ext/pitchfork_http/httpdate.c".freeze, "ext/pitchfork_http/memory_page.c".freeze, "ext/pitchfork_http/pitchfork_http.c".freeze, "ext/pitchfork_http/pitchfork_http.rl".freeze, "ext/pitchfork_http/pitchfork_http_common.rl".freeze, "lib/pitchfork.rb".freeze, "lib/pitchfork/children.rb".freeze, "lib/pitchfork/chunked.rb".freeze, "lib/pitchfork/configurator.rb".freeze, "lib/pitchfork/const.rb".freeze, "lib/pitchfork/flock.rb".freeze, "lib/pitchfork/http_parser.rb".freeze, "lib/pitchfork/http_response.rb".freeze, "lib/pitchfork/http_server.rb".freeze, "lib/pitchfork/info.rb".freeze, "lib/pitchfork/launcher.rb".freeze, "lib/pitchfork/listeners.rb".freeze, "lib/pitchfork/mem_info.rb".freeze, "lib/pitchfork/message.rb".freeze, "lib/pitchfork/refork_condition.rb".freeze, "lib/pitchfork/select_waiter.rb".freeze, "lib/pitchfork/shared_memory.rb".freeze, "lib/pitchfork/socket_helper.rb".freeze, "lib/pitchfork/soft_timeout.rb".freeze, "lib/pitchfork/stream_input.rb".freeze, "lib/pitchfork/tee_input.rb".freeze, "lib/pitchfork/tmpio.rb".freeze, "lib/pitchfork/version.rb".freeze, "lib/pitchfork/worker.rb".freeze, "pitchfork.gemspec".freeze]
  s.homepage = "https://github.com/Shopify/pitchfork".freeze
  s.licenses = ["GPL-2.0+".freeze, "Ruby".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.5.0".freeze)
  s.rubygems_version = "3.6.9".freeze
  s.summary = "Rack HTTP server for fast clients and Unix".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<rack>.freeze, [">= 2.0".freeze])
  s.add_runtime_dependency(%q<logger>.freeze, [">= 0".freeze])
end
