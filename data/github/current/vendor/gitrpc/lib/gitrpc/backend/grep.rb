# rubocop:disable Style/FrozenStringLiteralComment

module GitRPC
  class Backend
    rpc_reader :grep
    def grep(patterns, dirs:, tree:)
      args = [
        "--line-number",
        "--extended-regexp",
        "--context=2",
        "--show-function",
      ]
      args += patterns.flat_map { |pattern|
        ["-e", pattern.respond_to?(:source) ? pattern.source : pattern]
      }
      args << tree
      args << "--"
      args += dirs
      res = spawn_git("grep", args)
      raise GitRPC::CommandFailed.new(res) if res["status"] > 1
      chunks = res["out"].split(/^--\n/)

      chunks = combine_function_chunks(chunks)

      # turn the chunks into hashes
      chunks.map do |chunk|
        files, linenos, lines = chunk.lines.map { |l| l.split(/[=:-]/, 3) }.transpose
        filename = files.first

        context, lines, linenos = function_context(lines, linenos)
        lines, linenos = trim_blank_lines(lines, linenos)

        {
          filename: filename,
          first_line: linenos.first.to_i,
          last_line: linenos.last.to_i,
          code: lines.join(""),
          context: context,
        }
      end
    end

    def combine_function_chunks(chunks)
      return chunks unless chunks.length > 1

      combined = false

      # the [nil] is to keep the last chunk from being dropped if it doesn't get combined
      chunks = (chunks + [nil]).each_cons(2).collect do |a, b|
        if combined
          combined = false
          next
        end

        if a.lines.length == 1
          combined = true
          [a, b].join("")
        else
          combined = false
          [a, b]
        end
      end.compact.collect { |x| Array(x).first }

      chunks
    end

    def function_context(lines, linenos)
      # If there are more than 5 lines, that means "function" hunk context was
      # added to this chunk. Take it back out and turn it into a line/lineno hash.
      context = if lines.length > 5
        { line: lines.shift, lineno: linenos.shift.to_i }
      end

      [context, lines, linenos]
    end

    def trim_blank_lines(lines, linenos)
      2.times do
        [lines, linenos].each(&:shift) if lines.first.empty?
        [lines, linenos].each(&:pop)   if lines.last.empty?
      end

      [lines, linenos]
    end
  end
end
