# frozen_string_literal: true
# typed: true

module GitRPC
  class Client
    # Public: Update ref to a new OID.
    #
    # Any ref, including private ones, maybe be updated. Ensure user inputs are
    # sanitized.
    #
    # ref            - String Ref name
    # new_value      - String OID
    # old_value      - String OID (default: nil)
    # dgit_disabled  - disable dgit (for use in tests only)
    # committer_date - committer date
    # repairing      - This function is used for repairs.
    #
    # Returns nothing or raises a GitRPC::RefUpdateError exception if the update
    # failed.
    def update_ref(ref, new_value, options = {})
      ensure_valid_refname(ref)
      ensure_valid_full_oid(new_value)
      old_value = options.delete(:old_value)
      ensure_valid_full_oid(old_value) if old_value

      send_message(:update_ref, ref, new_value, old_value, **options)

      nil
    ensure
      if !options[:repairing]
        clear_repository_reference_key!
      end
    end

    # Public: Update multiple refs.
    #
    # Any ref, including private ones, maybe be updated. Ensure user inputs are
    # sanitized.
    #
    # batch           - newline-separated operations, a la `git update-ref --stdin`
    # reason          - message for the reflog
    # dgit_disabled   - disable dgit (for use in tests only)
    # committer_date  - committer date
    # committer_name  - committer name
    # committer_email - committer email
    # pusher          - pusher
    # sockstat_env    - a Hash with "GIT_SOCKSTAT_VAR_" keys
    # tz              - timezone
    #
    # Returns nothing or raises a GitRPC::RefUpdateError exception if the update
    # failed.
    def update_ref_batch(batch, options = {})
      send_message(:update_ref_batch, batch, **options)

      nil
    ensure
      clear_repository_reference_key!
    end

    # Public: Delete ref.
    #
    # ref            - String Ref name
    # old_value      - String OID (default: nil)
    # dgit_disabled  - disable dgit (for use in tests only)
    # committer_date - committer date
    #
    # Returns nothing or raises a GitRPC::RefUpdateError exception if the update
    # failed.
    def delete_ref(ref, options = {})
      ensure_valid_refname(ref)
      old_value = options.delete(:old_value)
      ensure_valid_full_oid(old_value) if old_value

      send_message(:delete_ref, ref, old_value, **options)

      nil
    ensure
      clear_repository_reference_key!
    end

    # Public: Update a symbolic reference
    #
    # ref       - String Ref name
    # new_value - String Ref name it should point to
    #
    # Returns nothing or raises a GitRPC::RefUpdateError exception if the update
    # failed.
    def update_symbolic_ref(ref, new_value)
      send_message(:update_symbolic_ref, ref, new_value)
    ensure
      clear_repository_reference_key!
    end
  end
end
