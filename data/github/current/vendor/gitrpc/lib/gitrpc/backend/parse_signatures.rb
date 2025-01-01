# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    GPG_SIGNATURE_PREFIX   = "-----BEGIN PGP SIGNATURE-----".freeze
    SMIME_SIGNATURE_PREFIX = "-----BEGIN SIGNED MESSAGE-----".freeze
    SSH_SIGNATURE_PREFIX   = "-----BEGIN SSH SIGNATURE-----".freeze
    GPGSIG_FIELD           = "gpgsig ".freeze

    # Read the signature and signing payload from commit headers.
    #
    # oids - An Array of String OIDs. Must be 40 char sha1s.
    #
    # See Client#parse_commit_signature for usage documentation.
    rpc_reader :parse_commit_signatures
    def parse_commit_signatures(oids)
      parse_object_signatures(oids, "commit") do |commit|
        commit_message_index = commit.index("\n\n")
        lines = commit[0..commit_message_index].lines
        result = []
        lines.each_with_index { |line, index|
          if line.start_with?(GPGSIG_FIELD)
            commit_payload = lines[0..index - 1].join
            # Remove the leading space from the signature
            end_of_signature = search_end_of_signature(lines, index + 1)
            additional_info = lines[end_of_signature..-1].join
            commit_signature = lines[index..end_of_signature - 1].map { |l|
              l.start_with?(" ") ? l[1..-1] : l
            }.join[GPGSIG_FIELD.size..-2]

            result = (commit_message_index != nil) ? [commit_signature, "#{commit_payload}#{additional_info}\n#{commit[commit_message_index + 2..-1]}"] : [commit_signature, commit_payload]
            break
          end
        }

        result.length > 0 ? result : false
      end
    end

    def search_end_of_signature(lines, index)
      end_of_signature = index
      while end_of_signature < lines.length
        if !lines[end_of_signature].start_with?(" ")
          return end_of_signature
        end
        end_of_signature += 1
      end
      end_of_signature
    end

    # Read the signatures and signing payloads from tags.
    #
    # oids - An Array of String OIDs. Must be 40 char sha1s.
    #
    # See Client#parse_tag_signatures for usage documentation.
    rpc_reader :parse_tag_signatures
    def parse_tag_signatures(oids)
      parse_object_signatures(oids, "tag") do |tag|
        signature_start_index = tag.rindex(GPG_SIGNATURE_PREFIX) || tag.rindex(SMIME_SIGNATURE_PREFIX) || tag.rindex(SSH_SIGNATURE_PREFIX)
        if signature_start_index.nil?
          false
        else
          ["#{tag[signature_start_index..-1]}", tag[0..signature_start_index - 1]]
        end
      end
    end

    def raise_invalid_object(content)
      if m = content.match(/^(.*) (missing|ambiguous)$/)
        raise GitRPC::ObjectMissing.new("bad object", m.captures[0])
      end
    end

    def parse_object_signatures(oids, type)
      res = spawn_git("cat-file", ["--batch"], oids.join("\n"))
      signatures = []

      if res["ok"]
        response = res["out"][0..-2]
        index = 0
        while index < response.length
          end_of_header = response[index..-1].index("\n")

          if end_of_header.nil?
            ## A single missing/ambiguous object has been asked for
            raise_invalid_object(response[index..-1])
          end

          header = response[index, end_of_header]

          parsed_header = header.split(" ")
          if parsed_header.length != 3
            # Multiple oids has been asked for, and at least one of then is not correct
            raise_invalid_object(header)
          end
          raise GitRPC::InvalidObject.new("invalid object {#{parsed_header[0]}}") if parsed_header[1] != type
          size = parsed_header[2].chomp.to_i
          start_processing = 1 + header.size
          content = response[start_processing + index..header.size + index + size]
          index += start_processing + size + 1
          signatures << yield(content)
        end

        signatures
      else
        raise GitRPC::InvalidObject.new("unknown error: #{res["err"]}")
      end
    end
  end
end
