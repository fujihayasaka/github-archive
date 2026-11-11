# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    rpc_reader :read_submodules
    def read_submodules(oid)
      # git config --blob HEAD:.gitmodules --list
      # submodule.vendor/libgit2.path=vendor/libgit2
      # submodule.vendor/libgit2.url=https://github.com/libgit2/libgit2.git
      modules = spawn_git("config", ["--blob", "#{oid}:.gitmodules", "--list"])
      if modules["ok"]
        res = modules["out"].each_line.with_object({}) do |line, submodules|
          if line =~ %r{submodule\.(.*)\.([^.=]+)=(.*)$}
            name = $1
            type = $2
            value = $3

            submodules[name] ||= {}
            submodules[name][type] = value.strip
          end
        end
        format_submodules(res)
      else
        # Error processing submodules, return nothing
        []
      end
    end

    def format_submodules(submodules)
      submodules.map do |name, submodule|
        next unless submodule.keys.include?("path") && submodule.keys.include?("url")
        submodule["name"] = name
        submodule
      end.compact
    end
  end
end
