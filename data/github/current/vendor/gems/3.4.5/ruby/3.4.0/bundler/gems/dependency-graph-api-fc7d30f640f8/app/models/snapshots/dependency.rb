module Snapshots
  class Dependency
    attr_reader :name, :version, :scope, :purl

    def initialize(name: nil, version: nil, scope: nil, purl: nil)
      @name = purl&.name || name
      @version = purl&.version || version
      @scope = scope
      @purl = purl
    end

    def ==(other)
      @name == other.name && @version == other.version && @scope == other.scope
    end

    def <=>(other)
      key.<=>(other.key)
    end

    def eql?(other)
      self.==(other)
    end

    def key
      "#{@name}:#{@version}:#{@scope}"
    end

    def hash
      key.hash
    end
  end
end
