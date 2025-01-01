# frozen_string_literal: true

module GitRPC
  class Backend
    rpc_writer :rsync, no_git_repo: true
    def rsync(src, dest, archive: nil, recursive: nil, verbose: nil, hard_links: nil, delete: nil, checksum: nil, append: nil, stats: nil, ignore_missing: nil, include: [], exclude: [])
      argv = ["rsync"]
      if faster_cipher
        # faster cipher, disable pseudo tty alloc
        argv.push "-e", "ssh -T -c #{faster_cipher}"
      end

      argv << "-a" if archive
      argv << "-r" if recursive
      argv << "-v" if verbose
      argv << "-H" if hard_links
      argv << "--delete" if delete
      argv << "--checksum" if checksum
      argv << "--append" if append
      argv << "--stats" if stats
      argv << "--ignore-missing-args" if ignore_missing
      include.each { |x| argv << "--include=#{x}" }
      exclude.each { |x| argv << "--exclude=#{x}" }
      argv += ["--", src, dest]

      res = spawn(argv)
      {"ok" => res["ok"], "out" => res["out"], "err" => res["err"], "status" => res["status"]}
    end

    # Query ssh for available ciphers, and return a fast one if we find it.
    def faster_cipher
      if @fast_cipher_memo.nil?
        IO.popen(["ssh", "-Q", "cipher"]) { |ssh_io|
          @fast_cipher_memo = ssh_io.find {
              |cipher| cipher =~ /^aes128-gcm@openssh.com$/
          } || ""
        }
        @fast_cipher_memo = @fast_cipher_memo.strip
      end
      @fast_cipher_memo
    end
  end
end
