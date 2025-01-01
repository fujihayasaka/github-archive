# -*- encoding: utf-8 -*-
# stub: codeowners 0.0.2 ruby lib

Gem::Specification.new do |s|
  s.name = "codeowners".freeze
  s.version = "0.0.2".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Brandon Keepers".freeze]
  s.date = "1980-01-02"
  s.email = ["brandon@opensoul.org".freeze]
  s.files = [".gitattributes".freeze, ".github/workflows/ci.yml".freeze, ".gitignore".freeze, ".rubocop.yml".freeze, ".travis.yml".freeze, "CODEOWNERS".freeze, "Gemfile".freeze, "LICENSE".freeze, "README.md".freeze, "Rakefile".freeze, "bench/CODEOWNERS".freeze, "bench/bench.rb".freeze, "bench/diff-paths.txt".freeze, "bench/parse.rb".freeze, "bench/regexp.rb".freeze, "codeowners.gemspec".freeze, "lib/codeowners.rb".freeze, "lib/codeowners/matcher.rb".freeze, "lib/codeowners/matcher/graph.rb".freeze, "lib/codeowners/matcher/graph_builder.rb".freeze, "lib/codeowners/matcher/graph_visualizer.rb".freeze, "lib/codeowners/matcher/linear.rb".freeze, "lib/codeowners/matcher/node.rb".freeze, "lib/codeowners/matcher/path_tree.rb".freeze, "lib/codeowners/matcher/result.rb".freeze, "lib/codeowners/matcher/rule_graph.rb".freeze, "lib/codeowners/multibyte_parser.rb".freeze, "lib/codeowners/owner.rb".freeze, "lib/codeowners/owner_resolver.rb".freeze, "lib/codeowners/parser.rb".freeze, "lib/codeowners/pattern.rb".freeze, "lib/codeowners/rule.rb".freeze, "lib/codeowners/source_error.rb".freeze, "lib/codeowners/tree.rb".freeze, "lib/codeowners/version.rb".freeze, "test/file_test.rb".freeze, "test/matcher/graph_builder_test.rb".freeze, "test/matcher/graph_test.rb".freeze, "test/matcher/node_test.rb".freeze, "test/matcher/result_test.rb".freeze, "test/mulitbyte_parser_test.rb".freeze, "test/owner_test.rb".freeze, "test/owners_test.rb".freeze, "test/parser_test.rb".freeze, "test/pattern_test.rb".freeze, "test/rule_test.rb".freeze, "test/shared_parser_test.rb".freeze]
  s.homepage = "".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "3.6.7".freeze
  s.summary = "List the members of a CODEOWNERS file.".freeze
  s.test_files = ["test/file_test.rb".freeze, "test/matcher/graph_builder_test.rb".freeze, "test/matcher/graph_test.rb".freeze, "test/matcher/node_test.rb".freeze, "test/matcher/result_test.rb".freeze, "test/mulitbyte_parser_test.rb".freeze, "test/owner_test.rb".freeze, "test/owners_test.rb".freeze, "test/parser_test.rb".freeze, "test/pattern_test.rb".freeze, "test/rule_test.rb".freeze, "test/shared_parser_test.rb".freeze]

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<pathspec>.freeze, ["~> 2.1.0".freeze])
  s.add_development_dependency(%q<minitest>.freeze, ["~> 5.9".freeze])
  s.add_development_dependency(%q<rake>.freeze, ["~> 13.0".freeze])
  s.add_development_dependency(%q<benchmark-ips>.freeze, ["~> 2.7".freeze])
  s.add_development_dependency(%q<ruby-prof>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rubocop-performance>.freeze, [">= 0".freeze])
end
