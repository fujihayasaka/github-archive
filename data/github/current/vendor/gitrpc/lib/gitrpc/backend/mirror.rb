# frozen_string_literal: true
# typed: true

module GitRPC
  class Backend
    rpc_writer :fetch_for_mirror
    def fetch_for_mirror(url, refspecs, to_prefix, mirror_env)
      ref_specs = parse_refspecs_for_mirror(refspecs, to_prefix)

      args = ["--no-tags", url] + ref_specs
      res = spawn_git("fetch", args, nil, mirror_env)

      raise GitRPC::CommandFailed.new(res) unless res["ok"]
      read_refs("all").select { |name, _| name.start_with?(to_prefix) }
    end

    rpc_writer :delete_mirror_temp_refs
    def delete_mirror_temp_refs(mirror_prefix, cutoff, mirror_env)
      all_refs = read_refs("all")
      temp_refs = all_refs.keys.select do |name|
        name.start_with?(mirror_prefix) ||
          (name =~ %r{^refs/__gh__/temp/mirror-\d+-(\d+)} && $1.to_i < cutoff)
      end
      if temp_refs.any?
        delete_list = temp_refs.map { |name|
          "delete #{name}\n"
        }.join
        res = spawn_git("update-ref", ["-m", "mirror", "--stdin"], delete_list, mirror_env)
        raise GitRPC::CommandFailed.new(res) unless res["ok"]
      end
      "ok"
    end

    private

    def parse_refspecs_for_mirror(refspecs, to_prefix)
      if refspecs.is_a?(String)
        ["#{refspecs}*:#{to_prefix}*"]
      else
        refspecs.map do |refspec|
          from, to = refspec.split(":")
          to = "refs/*" if to.nil?
          "#{from}:#{to_prefix}#{to}"
        end
      end
    end
  end
end
