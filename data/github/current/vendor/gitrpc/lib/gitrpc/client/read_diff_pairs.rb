# typed: true
# frozen_string_literal: true

module GitRPC
  class Client
    def read_diff_pairs_with_base(oid1, oid2, base_oid, deltas, opts = {})
      timeout = opts["timeout"]

      raise GitRPC::Timeout if timeout && timeout <= 0

      delta_buffer = deltas.map { |d| d.to_raw }

      # FIXME: After we are fully on 2.7, we can remove this line that explicitly
      # symbolizes as well as the matching line in backend/read_diff_pairs stringifying.
      # 2.7 will honor key types, but 2.6 does not allow string keyed hashes to be
      # splatted out for kwargs.
      opts = symbolize_keys(opts)
      send_message(:read_diff_pairs_with_base, oid1, oid2, base_oid, delta_buffer.join, **opts)
    end
  end
end
