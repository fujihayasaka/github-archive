# -*- encoding: utf-8 -*-
# stub: rubocop-github 0.21.0 ruby lib

Gem::Specification.new do |s|
  s.name = "rubocop-github".freeze
  s.version = "0.21.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["GitHub".freeze]
  s.date = "2025-10-24"
  s.description = "Code style checking for GitHub Ruby repositories ".freeze
  s.email = "engineering@github.com".freeze
  s.files = ["LICENSE".freeze, "README.md".freeze, "STYLEGUIDE.md".freeze, "config/default.yml".freeze, "config/default_cops.yml".freeze, "config/default_pending.yml".freeze, "config/rails.yml".freeze, "config/rails_cops.yml".freeze, "config/rails_pending.yml".freeze, "guides/rails-controller-render-shorthand.md".freeze, "guides/rails-render-literal.md".freeze, "lib/rubocop-github-rails.rb".freeze, "lib/rubocop-github.rb".freeze, "lib/rubocop/cop/github.rb".freeze, "lib/rubocop/cop/github/avoid_object_send_with_dynamic_method.rb".freeze, "lib/rubocop/cop/github/insecure_hash_algorithm.rb".freeze, "lib/rubocop/cop/github/rails_controller_render_action_symbol.rb".freeze, "lib/rubocop/cop/github/rails_controller_render_literal.rb".freeze, "lib/rubocop/cop/github/rails_controller_render_paths_exist.rb".freeze, "lib/rubocop/cop/github/rails_controller_render_shorthand.rb".freeze, "lib/rubocop/cop/github/rails_render_object_collection.rb".freeze, "lib/rubocop/cop/github/rails_view_render_literal.rb".freeze, "lib/rubocop/cop/github/rails_view_render_paths_exist.rb".freeze, "lib/rubocop/cop/github/rails_view_render_shorthand.rb".freeze, "lib/rubocop/cop/github/render_literal_helpers.rb".freeze, "lib/rubocop/github.rb".freeze, "lib/rubocop/github/inject.rb".freeze]
  s.homepage = "https://github.com/github/rubocop-github".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.5.0".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "RuboCop GitHub".freeze

  s.installed_by_version = "3.5.22".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<rubocop>.freeze, [">= 1.37".freeze])
  s.add_runtime_dependency(%q<rubocop-performance>.freeze, [">= 1.15".freeze])
  s.add_runtime_dependency(%q<rubocop-rails>.freeze, [">= 2.17".freeze])
  s.add_development_dependency(%q<actionview>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<minitest>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
end
