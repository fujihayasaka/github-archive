# typed: true
# frozen_string_literal: true

module Repository::SlumlordDependency
  extend T::Sig
  extend T::Helpers

  abstract!

  sig { abstract.returns(Git::Ref::Collection) }
  def all_refs; end

  sig do
    abstract.
    type_parameters(:U).
    params(result_if_offline: T.type_parameter(:U)).
    returns(T.type_parameter(:U))
  end
  def rescue_offline(result_if_offline:); end

  sig { abstract.returns(GitRPC::Client) }
  def rpc; end

  sig do
    abstract.
    params(
      key: T.any(String, Symbol),
      payload: T::Hash[T.untyped, T.untyped],
      block: T.nilable(T.proc.void)
    ).
    void
  end
  def instrument(key, payload, &block); end

  def svn_in_use?
    if @svn_in_use.nil?
      @svn_in_use = all_refs.exist?("refs/__gh__/svn/v3") || all_refs.exist?("refs/__gh__/svn/v4") || !!rpc.fs_exist?("svn.history.msgpack")
    end
    @svn_in_use
  end

  def svn_blocked?
    svn_status == :disabled
  end

  def svn_status
    @svn_status ||=
        rescue_offline(result_if_offline: :offline) do
          if rpc.config_get("github.blocksvn") == "true"
            :disabled
          else
            :enabled
          end
        end
  end

  def block_svn
    GitHub::DGit::Util.config_store(self, "github.blocksvn", true)
    instrument :disable_svn, prefix: :staff
    @svn_status = :disabled
  end

  def unblock_svn
    GitHub::DGit::Util.config_delete(self, "github.blocksvn")
    instrument :enable_svn, prefix: :staff
    @svn_status = :enabled
  end

  def svn_toggle_blocked
    if svn_blocked?
      unblock_svn
    else
      block_svn
    end
  end

  def svn_debugging?
    if @svn_debugging.nil?
      @svn_debugging = false
      if expires = rpc.config_get("github.debug-svn-until")
        begin
          if expires > Time.now
            @svn_debugging = expires
          end
        rescue ArgumentError
          # not valid means no debugging
        end
      end
    end
    @svn_debugging
  end

  def debug_svn
    expires = 1.day.from_now
    GitHub::DGit::Util.config_store(self, "github.debug-svn-until", expires.iso8601)
    @svn_debugging = expires
  end

  def undebug_svn
    GitHub::DGit::Util.config_delete(self, "github.debug-svn-until")
    # Legacy debug flag
    GitHub::DGit::Util.config_delete(self, "github.debugsvn")
    @svn_debugging = false
  end

  def svn_toggle_debugging
    if svn_debugging?
      undebug_svn
    else
      debug_svn
    end
  end
end
