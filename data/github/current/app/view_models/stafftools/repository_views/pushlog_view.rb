# typed: true
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    class PushlogView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include UrlHelper

      attr_reader :entries

      ALLOWLIST = [:time, :receive_pack_size, :user_login, :pusher, :non_fast_forward, :merge_button, :pull_request_id, :via]
      def pretty_entries
        reflog_entries = []

        entries.each do |entry|
          entry_as_hash = entry.to_hash
          filtered_entry = entry_as_hash.select { |key, value| ALLOWLIST.include? key and !value.nil? }

          filtered_entry[:targets] = entry.targets.collect do |target|
            { ref: target.ref.force_encoding("utf-8").scrub!, before: target.before, after: target.after }
          end

          if !entry.pull_request_id.nil?
            num = if entry.pull_request
              entry.pull_request.number
            else
              "N/A (deleted)"
            end
            filtered_entry[:pull_request_id] = num
          end

          if !entry.non_fast_forward.nil?
            if entry.non_fast_forward
              filtered_entry[:force_push] = entry.non_fast_forward
            end

            filtered_entry.delete(:non_fast_forward)
          end

          if entry.deploy_key?
            filtered_entry[:deploy_key_verifier_login] = entry.pubkey_verifier_login
            filtered_entry[:deploy_key_fingerprint]    = entry.pubkey_fingerprint
          end

          reflog_entries << filtered_entry
        end

        JSON.pretty_generate reflog_entries
      end
    end
  end
end
