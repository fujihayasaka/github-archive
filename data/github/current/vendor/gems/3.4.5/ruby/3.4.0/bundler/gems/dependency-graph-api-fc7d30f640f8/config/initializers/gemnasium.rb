# Hack up original Gemnasium `dependency(match)` method to:
#   a) *Not* exclude gems with :git and :github options
#   b) Preserve dependency `opts`, which contains git URIs and github NWOs
class Gemnasium::Parser::Gemfile
  def dependency(match)
    opts = Gemnasium::Parser::Patterns.options(match["opts"])
    clean!(match, opts)
    name, reqs = match["name"], [match["req1"], match["req2"]].compact
    dependency = Bundler::Dependency.new(name, reqs, opts).tap do |dep|
      line = content.slice(0, match.begin(0)).count("\n") + 1
      dep.instance_variable_set(:@line, line)
    end

    DependencyWrapper.new(dependency, opts)
  end

  class DependencyWrapper < SimpleDelegator
    attr_reader :options

    def initialize(delegate, opts)
      @options = opts
      super(delegate)
    end
  end
end
