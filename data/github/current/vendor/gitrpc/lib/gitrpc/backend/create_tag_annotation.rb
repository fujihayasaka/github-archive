# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

require "date"

module GitRPC
  class Backend
    @@unix_epoch = Time.at(0).utc

    # This creates a ref, do we need to 3PC?
    rpc_writer :create_tag_annotation
    def create_tag_annotation(tag_name, target_oid, annotation)
      tagger_name = annotation["tagger"]["name"]
      tagger_email = annotation["tagger"]["email"]
      tagger_time = iso8601(annotation["tagger"]["time"])

      # Git doesn't handle dates before the UNIX Epoch so we need to clamp the date
      tagger_time = [tagger_time, @@unix_epoch].max

      env = {
        "GIT_COMMITTER_NAME" => tagger_name,
        "GIT_COMMITTER_EMAIL" => tagger_email,
        "GIT_COMMITTER_DATE" => tagger_time.iso8601,
      }

      args = ["--annotate", "--no-update-ref", "--cleanup=verbatim", "--file=-", "--", tag_name, target_oid]
      res = spawn_git("tag", args, annotation["message"], env)
      if res["ok"]
        res["out"].force_encoding("UTF-8").chomp
      elsif res["err"].include?(NOT_GIT_REPO)
        raise GitRPC::InvalidRepository, "path is not a repository: #{@path}"
      elsif res["err"] =~ /bad object type/
        raise GitRPC::InvalidObject.new("invalid object: #{target_oid}")
      elsif res["err"] =~ /[Ff]ailed to resolve '(\w+)' as a valid ref/
        raise GitRPC::ObjectMissing.new("no such object: #{target_oid}")
      else
        raise GitRPC::CommandFailed.new(res)
      end
    end
  end
end
