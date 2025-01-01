# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

# Loaded by script/console. Land helpers here.

GITRPC_REPO = File.expand_path("../../../.git", __FILE__)

# Initialize a GitRPC::Backend for a repo at the path
# passed in; Which defaults to the gitrpc repo itself.
def backend(path = GITRPC_REPO)
  GitRPC::Backend.new(path)
end

# Initialize a GitRPC::Client for a repo at the path
# passed in; Which defaults to the gitrpc repo itself.
def client(path = GITRPC_REPO)
  cache_store = {}
  cache = GitRPC::Util::HashCache.new(cache_store)
  lazy_cache = GitRPC::Util::HashCache::Lazy.new(cache_store)
  GitRPC::Client.new(backend(path), cache, lazy_cache)
end

# Initialize a GitRPC::Client for a repo at the path passed in.
def rpc(path)
  client(path)
end

Pry.config.prompt = lambda do |context, nesting, pry|
  "[gitrpc] #{context}> "
end
