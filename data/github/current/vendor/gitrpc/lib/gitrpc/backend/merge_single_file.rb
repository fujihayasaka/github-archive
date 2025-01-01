# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    EMPTY_BLOB_OID = "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"
    EXECUTABLE_BLOB_MODE = 0100755

    def pick_best_path(ancestor, ours, theirs)
      ancestor, ours, theirs = [ancestor, ours, theirs].map { |arg| arg ? arg[:path] : nil }.to_a
      if ancestor
        if ours && ancestor == ours
          theirs
        elsif theirs && ancestor == theirs
          ours
        else
          nil
        end
      else
        nil
      end
    end

    def pick_best_mode(ancestor, ours, theirs)
      ancestor, ours, theirs = [ancestor, ours, theirs].map { |arg| arg ? arg[:filemode] : nil }.to_a
      if ancestor
        ancestor == ours ? theirs : ours
      elsif ours && theirs
        if [ours, theirs].include? EXECUTABLE_BLOB_MODE
          EXECUTABLE_BLOB_MODE
        else
          0100644
        end
      else
        0
      end
    end

    rpc_reader :merge_single_file
    def merge_single_file(ancestor, ours, theirs, options = {})
      options[:our_label] ||= "ours"
      options[:their_label] ||= "theirs"

      result = spawn_git(
        "merge-file", [
          "-L#{options[:our_label]}",
          "-Lbase",
          "-L#{options[:their_label]}",
          "-p",
          "--object-id",
          ours[:oid],
          ancestor ? ancestor[:oid] : EMPTY_BLOB_OID,
          theirs[:oid],
        ],
        nil,
        {},
        nil,
        nil,
        [
          "-c", "merge.renames=false",
          "-c", "rerere.enabled=false",
        ]
      )

      if result["signaled"]
        raise GitRPC::Failure.new GitRPC::CommandFailed.new(result)
      end

      case result["status"]
      when 0..127
        {
          automergeable: result["status"] == 0,
          path: pick_best_path(ancestor, ours, theirs),
          filemode: pick_best_mode(ancestor, ours, theirs),
          data: result["out"],
        }
      else
        if result["err"].include?(NOT_GIT_REPO)
          raise GitRPC::InvalidRepository, "path is not a repository: #{@path}"
        elsif result["err"] =~ /cannot merge binary files/i
          {
            automergeable: false,
            path: nil,
            filemode: 0,
            data: "",
          }
        else
          raise GitRPC::Failure.new GitRPC::CommandFailed.new(result)
        end
      end
    end
  end
end
